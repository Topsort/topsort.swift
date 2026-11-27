import Foundation
#if canImport(UIKit) && !os(watchOS)
    import UIKit
#endif

private let EVENTS_TOPSORT_URL = URL(string: "https://api.topsort.com/v2/events")!

class EventManager {
    static let shared = EventManager()
    private let serialQueue = DispatchQueue(label: "com.topsort.analytics.EventManager")
    private var periodicEvent: PeriodicEvent
    @FilePersistedValue(storePath: PathHelper.path(for: "com.topsort.analytics.event-queue.plist"))
    var _eventQueue: [EventItem]?
    private var eventQueue: [EventItem] {
        get {
            if let eq = _eventQueue {
                return eq
            } else {
                _eventQueue = []
                return []
            }
        }
        set {
            _eventQueue = newValue
        }
    }

    @FilePersistedValue(storePath: PathHelper.path(for: "com.topsort.analytics.pending-events.plist"))
    var _pendingEvents: [UUID: PendingEvents]?
    private var pendingEvents: [UUID: PendingEvents] {
        get {
            if let pe = _pendingEvents {
                return pe
            } else {
                _pendingEvents = [:]
                return [:]
            }
        }
        set {
            _pendingEvents = newValue
        }
    }

    private var inProgress: Set<UUID> = []
    private var queueAtCapacityLogged = false
    var onEventsDiscarded: ((DiscardReason, Int) -> Void)?
    var flushAt: Int = 30
    var flushInterval: TimeInterval = 30
    private var lifecycleObserver: LifecycleObserver?
    #if canImport(Network)
        var networkMonitor: NetworkMonitoring
    #endif
    #if canImport(UIKit) && !os(watchOS)
        /// Held from the background flush until the last in-flight request returns, so the
        /// system does not suspend the process mid-send. Main thread only.
        private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
        var backgroundTasks: BackgroundTaskProviding = UIApplicationBackgroundTasks()
        var isHoldingBackgroundTask: Bool {
            backgroundTask != .invalid
        }
    #endif

    private init() {
        client = HTTPClient(apiKey: nil)
        #if canImport(Network)
            networkMonitor = NetworkMonitor()
        #endif
        // The queue can afford the 5 s debounce: a lost write costs at most a few events. The
        // pending set is the at-least-once ledger — a batch acknowledged in memory but still on
        // disk is re-sent after a crash and billed twice — so every change is written right away.
        __eventQueue.deferPersistence = true
        periodicEvent = PeriodicEvent(interval: 30, action: { EventManager.shared.handlePeriodicEvent() })
        periodicEvent.start()
        lifecycleObserver = LifecycleObserver(
            onBackground: { [weak self] in
                Logger.debug("App entering background — flushing and persisting events")
                self?.beginBackgroundTask()
                self?.flushAndPersist()
                self?.endBackgroundTaskIfIdle()
            },
            onTerminate: { [weak self] in
                Logger.debug("App terminating — flushing and persisting events")
                self?.flushAndPersist()
            }
        )
        #if canImport(Network)
            networkMonitor.onConnectivityRestored = { [weak self] in
                self?.flush()
            }
            networkMonitor.start()
        #endif
    }

    var url: URL = EVENTS_TOPSORT_URL
    var client: HTTPClient

    func configure(apiKey: String, url: String?, flushAt: Int? = nil, flushInterval: TimeInterval? = nil, onEventsDiscarded: ((DiscardReason, Int) -> Void)? = nil) throws(ConfigurationError) {
        if let flushAt = flushAt, flushAt < 1 {
            throw .invalidFlushAt(flushAt)
        }
        if let flushInterval = flushInterval, flushInterval <= 0 {
            throw .invalidFlushInterval(flushInterval)
        }
        if let url = url {
            guard let parsedURL = URL(string: "\(url)/events") else {
                throw .invalidURL(url)
            }
            self.url = parsedURL
        }
        serialQueue.sync {
            self.client.apiKey = apiKey
            self.onEventsDiscarded = onEventsDiscarded
            if let flushAt = flushAt {
                self.flushAt = flushAt
            }
            if let flushInterval = flushInterval {
                self.flushInterval = flushInterval
                self.periodicEvent.stop()
                self.periodicEvent = PeriodicEvent(interval: flushInterval, action: { EventManager.shared.handlePeriodicEvent() })
                self.periodicEvent.start()
            }
        }
    }

    func push(event: EventItem) {
        serialQueue.async {
            self.eventQueue.append(event)
            if self.eventQueue.count > MAX_QUEUED_EVENTS {
                let dropped = self.eventQueue.count - MAX_QUEUED_EVENTS
                let evicted = Array(self.eventQueue.prefix(dropped))
                self.eventQueue.removeFirst(dropped)
                self.discarded(dropped, reason: .queueOverCapacity)
                self.lost(evicted)
                // Logged once per episode: at capacity every push sheds an event, and one
                // line per event would drown the log during a long outage.
                if !self.queueAtCapacityLogged {
                    self.queueAtCapacityLogged = true
                    Logger.warning("Event queue is at capacity (\(MAX_QUEUED_EVENTS)); dropping the oldest events until it drains")
                }
            } else {
                self.queueAtCapacityLogged = false
            }
            if self.eventQueue.count >= self.flushAt {
                self.performSend()
            }
        }
    }

    func flush() {
        serialQueue.async {
            self.performSend()
            self.performRetry()
        }
    }

    /// Synchronously flushes events and persists state to disk.
    /// Must NOT be called from within serialQueue — will deadlock.
    func flushAndPersist() {
        dispatchPrecondition(condition: .notOnQueue(serialQueue))
        serialQueue.sync {
            self.performSend()
            self.performRetry()
            self.__eventQueue.persistIfDirty()
            // Never dirty (it persists on every change); the call still drains its queued writes.
            self.__pendingEvents.persistIfDirty()
        }
    }

    /// Must be called on serialQueue
    private func performSend() {
        guard client.apiKey != nil else {
            Logger.debug("Not configured yet — deferring event send")
            return
        }
        #if canImport(Network)
            guard networkMonitor.isConnected else {
                Logger.debug("Offline — deferring event send")
                return
            }
        #endif
        while !eventQueue.isEmpty, inProgress.count < MAX_IN_PROGRESS {
            let batch = nextBatch()
            guard let data = encode(batch) else {
                continue
            }
            let id = UUID()
            let pending = PendingEvents(id: id, data: data, createdAt: Date(), retries: 0, lastRetry: Date())
            pendingEvents[id] = pending
            inProgress.insert(id)

            client.post(url: url, data: data, callback: { r in
                self.process_response(id: id, result: r)
            })
        }
    }

    /// Must be called on serialQueue. Takes events off the front of the queue up to
    /// MAX_EVENTS_PER_BATCH total, capping each event type at MAX_EVENTS_PER_TYPE_PER_BATCH so
    /// no array in the outgoing request exceeds the API's per-type limit; events past a type's
    /// cap are left in the queue, in order, for the next batch.
    private func nextBatch() -> [EventItem] {
        var counts: [EventItemKind: Int] = [:]
        var batch: [EventItem] = []
        var remainder: [EventItem] = []
        for item in eventQueue {
            if batch.count < MAX_EVENTS_PER_BATCH, (counts[item.kind] ?? 0) < MAX_EVENTS_PER_TYPE_PER_BATCH {
                counts[item.kind, default: 0] += 1
                batch.append(item)
            } else {
                remainder.append(item)
            }
        }
        eventQueue = remainder
        return batch
    }

    /// An event that cannot be serialized (a non-finite `Double` in a purchase, say) can
    /// never be sent; keeping it would stall every later batch behind it. Only the offending
    /// events are dropped, not the batch they happened to share.
    private func encode(_ batch: [EventItem]) -> Data? {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(batch.toEvents()) {
            return data
        }
        let encodable = batch.filter { (try? encoder.encode($0)) != nil }
        Logger.error("Dropping \(batch.count - encodable.count) events that cannot be serialized")
        discarded(batch.count - encodable.count, reason: .unserializable)
        lost(batch.filter { (try? encoder.encode($0)) == nil })
        guard !encodable.isEmpty else {
            return nil
        }
        return try? encoder.encode(encodable.toEvents())
    }

    private func process_response(id: UUID, result: Result<Data?, HTTPClientError>) {
        serialQueue.async {
            self.inProgress.remove(id)
            if self.inProgress.isEmpty {
                DispatchQueue.main.async { self.endBackgroundTaskIfIdle() }
            }
            switch result {
            case .success:
                self.pendingEvents.removeValue(forKey: id)
            case let .failure(error):
                if error.isRetriable() {
                    if var pendingEvents = self.pendingEvents[id], pendingEvents.retries < MAX_RETRIES {
                        pendingEvents.retries += 1
                        pendingEvents.lastRetry = Date()
                        self.pendingEvents[id] = pendingEvents
                        Logger.warning("Failed to send events, will retry: \(error)")
                    } else {
                        // Retries exhausted: retire the batch. Without this it stays in
                        // pendingEvents with a frozen retries/lastRetry, so retryAfter is
                        // permanently in the past and it is re-sent on every flush forever.
                        let batch = self.pendingEvents.removeValue(forKey: id)
                        Logger.error("Dropping events after \(MAX_RETRIES) failed retries: \(error)")
                        self.discarded(max(batch?.eventCount ?? 0, 1), reason: .retriesExhausted)
                        self.lost(batch)
                    }
                } else {
                    let batch = self.pendingEvents.removeValue(forKey: id)
                    Logger.error("Failed to send events (non-retriable): \(error)")
                    self.discarded(max(batch?.eventCount ?? 0, 1), reason: .permanentlyRejected)
                    self.lost(batch)
                }
            }
        }
    }

    /// For an event rejected before it was ever queued, so there is nothing to remove. Routed
    /// through the serial queue anyway so the callback runs where it always does.
    func discardInvalid() {
        serialQueue.async { self.discarded(1, reason: .invalidEvent) }
    }

    /// Must be called on serialQueue. A stored batch whose body no longer decodes still held at
    /// least one event, so it is never reported as zero.
    private func discarded(_ count: Int, reason: DiscardReason) {
        guard count > 0, let onEventsDiscarded else { return }
        onEventsDiscarded(reason, count)
    }

    /// Must be called on serialQueue. The API never accepted events given up on, so `Topsort` must
    /// not treat their bids as reported: the next report of each is sent rather than dropped.
    private func lost(_ items: [EventItem]) {
        guard !items.isEmpty else { return }
        Topsort.shared.forgetReports(in: items)
    }

    /// Must be called on serialQueue. A batch whose stored body no longer decodes has nothing to
    /// forget that can be identified.
    private func lost(_ batch: PendingEvents?) {
        guard let batch, let events = try? JSONDecoder().decode(Events.self, from: batch.data) else { return }
        lost(events.toItems())
    }

    /// Must be called on serialQueue
    private func performRetry() {
        guard client.apiKey != nil else {
            Logger.debug("Not configured yet — deferring event retry")
            return
        }
        #if canImport(Network)
            guard networkMonitor.isConnected else {
                Logger.debug("Offline — deferring event retry")
                return
            }
        #endif
        if inProgress.count >= MAX_IN_PROGRESS {
            return
        }
        let now = Date()
        let retryable = pendingEvents
            .values
            .filter { !inProgress.contains($0.id) && $0.retryAfter < now }
            .sorted(by: { a, b in a.retries < b.retries })
            .prefix(MAX_IN_PROGRESS - inProgress.count)
        for pendingEvent in retryable {
            inProgress.insert(pendingEvent.id)
            client.post(url: url, data: pendingEvent.data, callback: { r in
                self.process_response(id: pendingEvent.id, result: r)
            })
        }
    }

    private func handlePeriodicEvent() {
        flush()
    }

    #if canImport(UIKit) && !os(watchOS)
        private func beginBackgroundTask() {
            guard backgroundTask == .invalid else { return }
            backgroundTask = backgroundTasks.begin(name: "com.topsort.analytics.flush") { [weak self] in
                self?.endBackgroundTask()
            }
        }

        private func endBackgroundTaskIfIdle() {
            guard backgroundTask != .invalid else { return }
            let idle = serialQueue.sync {
                // Drain the ledger's queued writes first: releasing the task while the ack is
                // still on its way to disk would re-send the batch after a suspension.
                __pendingEvents.persistIfDirty()
                return inProgress.isEmpty
            }
            if idle {
                endBackgroundTask()
            }
        }

        private func endBackgroundTask() {
            guard backgroundTask != .invalid else { return }
            backgroundTasks.end(backgroundTask)
            backgroundTask = .invalid
        }
    #else
        private func beginBackgroundTask() {}
        private func endBackgroundTaskIfIdle() {}
    #endif
}
