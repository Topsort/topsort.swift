import Foundation

private let TOPSORT_URL = URL(string: "https://api.topsort.com/v2/events")!

enum EventItem: Codable {
    case click(Event)
    case impression(Event)
    case purchase(PurchaseEvent)
}

extension [EventItem] {
    func toEvents() -> Events {
        let (i, c, p) = self.reduce(([],[],[]), Self.agg)
        return Events(impressions: i, clicks: c, purchases: p)
    }

    private static func agg(r: ([Event], [Event], [PurchaseEvent]), e: EventItem) -> ([Event], [Event], [PurchaseEvent]) {
        let (i, c, p) = r
        switch e {
        case .click(let event):
            return (i, c + [event], p)
        case .impression(let event):
            return (i + [event], c, p)
        case .purchase(let event):
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
        get {
            let base = 10.0
            let max = 1200.0
            let exp = Double(retries)
            let wait = min(base * pow(2.0, exp), max)
            return lastRetry.addingTimeInterval(wait)
        }
    }
}

private let MAX_IN_PROGRESS = 10
private let MAX_RETRIES = 50

class EventManager {
    public static let shared = EventManager()
    private let serialQueue = DispatchQueue(label: "com.topsort.analytics.EventManager")
    private let periodicEvent = PeriodicEvent(interval: 60, action: { EventManager.shared.handlePeriodicEvent() })
    @FilePersistedValue(storePath: PathHelper.path(for: "com.topsort.analytics.event-queue.plist"))
    private var _eventQueue: [EventItem]?
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
    private var _pendingEvents: Dictionary<UUID, PendingEvents>?
    private var pendingEvents: Dictionary<UUID, PendingEvents> {
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
    private init() {
        self.client = HTTPClient(apiKey: nil)
        self.periodicEvent.start()
    }
    private var url: URL = TOPSORT_URL
    private var client: HTTPClient
    public func configure(apiKey: String, url: String?) {
        self.client.apiKey = apiKey
        if let url = url {
            guard let url = URL(string: url) else {
                fatalError("Invalid URL")
            }
            self.url = url
        }
    }

    public func push(event: EventItem) {
        serialQueue.async {
            self.eventQueue.append(event)
            self.send()
        }
    }

    private func send() {
        serialQueue.async {
            //TODO: check network connectivity
            if self.inProgress.count > MAX_IN_PROGRESS {
                return
            }
            if self.eventQueue.isEmpty {
                return
            }
            let events = self.eventQueue.toEvents()
            guard let data = try? JSONEncoder().encode(events) else {
                print("failed to serialize events: \(events)")
                return
            }
            let id = UUID()
            let pendingEvents = PendingEvents(id: id, data: data, createdAt: Date(), retries: 0, lastRetry: Date())
            self.pendingEvents[id] = pendingEvents
            self.inProgress.insert(id)

            self.client.post(url: self.url, data: data, callback: { r in
                self.process_response(id: id, result: r)
            })
            self.eventQueue = []
        }
    }

    private func process_response(id: UUID, result: Result<Data?, HTTPClientError>) {
        serialQueue.async {
            self.inProgress.remove(id)
            switch result {
                case .success(_):
                    self.pendingEvents.removeValue(forKey: id)
                case .failure(let error):
                    if error.isRetriable() {
                        if var pendingEvents = self.pendingEvents[id], pendingEvents.retries < MAX_RETRIES {
                            pendingEvents.retries += 1
                            pendingEvents.lastRetry = Date()
                            self.pendingEvents[id] = pendingEvents
                            print("failed to send events, backoff retry: \(error)")
                        }
                    } else {
                        self.pendingEvents.removeValue(forKey: id)
                        print("failed to send events: \(error)")
                    }
            }
        }
    }

    private func retry() {
        serialQueue.async {
            //TODO: check network connectivity - NWPathMonitor
            if self.inProgress.count > MAX_IN_PROGRESS {
                return
            }
            let now = Date()
            let pendingEvents = self
                .pendingEvents
                .values
                .filter({ !self.inProgress.contains($0.id) && $0.retryAfter < now })
                .sorted(by: {a, b in a.retries < b.retries})
                .prefix(MAX_IN_PROGRESS - self.inProgress.count)
            for pendingEvent in pendingEvents {
                self.inProgress.insert(pendingEvent.id)
                self.client.post(url: self.url, data: pendingEvent.data, callback: { r in
                    self.process_response(id: pendingEvent.id, result: r)
                })
            }
        }
    }

    private func handlePeriodicEvent() {
        send()
        retry()
    }

}
