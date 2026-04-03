import Foundation

private let EVENTS_TOPSORT_URL = URL(string: "https://api.topsort.com/v2/events")!

enum EventItem: Codable {
    case click(Event)
    case impression(Event)
    case purchase(PurchaseEvent)
}

extension [EventItem] {
    func toEvents() -> Events {
        let (i, c, p) = reduce(([], [], []), Self.agg)
        return Events(impressions: i, clicks: c, purchases: p)
    }

    private static func agg(r: ([Event], [Event], [PurchaseEvent]), e: EventItem) -> ([Event], [Event], [PurchaseEvent]) {
        let (i, c, p) = r
        switch e {
        case let .click(event):
            return (i, c + [event], p)
        case let .impression(event):
            return (i + [event], c, p)
        case let .purchase(event):
            return (i, c, p + [event])
        }
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

private let MAX_IN_PROGRESS = 10
private let MAX_RETRIES = 50

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
        __eventQueue.deferPersistence = true
        __pendingEvents.deferPersistence = true
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
        client.apiKey = apiKey
        if let url = url {
            guard let parsedURL = URL(string: "\(url)/events") else {
                throw .invalidURL(url)
            }
            self.url = parsedURL
        }
        serialQueue.sync {
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
            self.__pendingEvents.persistIfDirty()
        }
    }

    /// Must be called on serialQueue
    private func performSend() {
        #if canImport(Network)
            guard networkMonitor.isConnected else {
                Logger.debug("Offline — deferring event send")
                return
            }
        #endif
        if inProgress.count > MAX_IN_PROGRESS {
            return
        }
        if eventQueue.isEmpty {
            return
        }
        let events = eventQueue.toEvents()
        guard let data = try? JSONEncoder().encode(events) else {
            Logger.error("Failed to serialize events: \(events)")
            return
        }
        let id = UUID()
        let pending = PendingEvents(id: id, data: data, createdAt: Date(), retries: 0, lastRetry: Date())
        pendingEvents[id] = pending
        inProgress.insert(id)

        client.post(url: url, data: data, callback: { r in
            self.process_response(id: id, result: r)
        })
        eventQueue = []
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
        #if canImport(Network)
            guard networkMonitor.isConnected else {
                Logger.debug("Offline — deferring event retry")
                return
            }
        #endif
        if inProgress.count > MAX_IN_PROGRESS {
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
