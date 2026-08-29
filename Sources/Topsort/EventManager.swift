import Foundation

private let EVENTS_TOPSORT_URL = URL(string: "https://api.topsort.com/v2/events")!

enum EventItem: Codable {
    case click(Event)
    case impression(Event)
    case purchase(PurchaseEvent)
    case pageview(PageViewEvent)
}

extension [EventItem] {
    func toEvents() -> Events {
        var impressions: [Event] = []
        var clicks: [Event] = []
        var purchases: [PurchaseEvent] = []
        var pageviews: [PageViewEvent] = []
        for item in self {
            switch item {
            case let .impression(event): impressions.append(event)
            case let .click(event): clicks.append(event)
            case let .purchase(event): purchases.append(event)
            case let .pageview(event): pageviews.append(event)
            }
        }
        return Events(
            impressions: impressions.isEmpty ? nil : impressions,
            clicks: clicks.isEmpty ? nil : clicks,
            purchases: purchases.isEmpty ? nil : purchases,
            pageviews: pageviews.isEmpty ? nil : pageviews
        )
    }
}

struct PendingEvents: Codable {
    let id: UUID
    let data: Data
    let createdAt: Date
    var retries: Int
    var lastRetry: Date
    var retryAfter: Date {
        let base = 10.0
        let max = 1200.0
        let exp = Double(retries)
        let wait = min(base * pow(2.0, exp), max)
        return lastRetry.addingTimeInterval(wait)
    }
}

let MAX_IN_PROGRESS = 10
let MAX_RETRIES = 50
/// Resource bound on the queue. Events are dropped oldest-first past this, rather than by
/// age: how long an event stays attributable is a server-side decision the client cannot know.
let MAX_QUEUED_EVENTS = 5000
/// Cap on a single POST body. Past this the request risks a 413, which is non-retriable and
/// would discard the whole batch.
let MAX_EVENTS_PER_BATCH = 500

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
    var flushAt: Int = 30
    var flushInterval: TimeInterval = 30
    private var lifecycleObserver: LifecycleObserver?
    #if canImport(Network)
        var networkMonitor: NetworkMonitoring
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
                self?.flushAndPersist()
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

    func configure(apiKey: String, url: String?, flushAt: Int? = nil, flushInterval: TimeInterval? = nil) throws(ConfigurationError) {
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
                self.eventQueue.removeFirst(self.eventQueue.count - MAX_QUEUED_EVENTS)
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
            let batch = Array(eventQueue.prefix(MAX_EVENTS_PER_BATCH))
            eventQueue.removeFirst(batch.count)
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
        guard !encodable.isEmpty else {
            return nil
        }
        return try? encoder.encode(encodable.toEvents())
    }

    private func process_response(id: UUID, result: Result<Data?, HTTPClientError>) {
        serialQueue.async {
            self.inProgress.remove(id)
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
                        self.pendingEvents.removeValue(forKey: id)
                        Logger.error("Dropping events after \(MAX_RETRIES) failed retries: \(error)")
                    }
                } else {
                    self.pendingEvents.removeValue(forKey: id)
                    Logger.error("Failed to send events (non-retriable): \(error)")
                }
            }
        }
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
}
