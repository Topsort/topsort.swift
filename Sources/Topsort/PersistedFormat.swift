import Foundation

enum EventItem: Codable {
    case click(Event)
    case impression(Event)
    case purchase(PurchaseEvent)
    case pageview(PageViewEvent)
    case render(RenderEvent)

    var kind: EventItemKind {
        switch self {
        case .click: return .click
        case .impression: return .impression
        case .purchase: return .purchase
        case .pageview: return .pageview
        case .render: return .render
        }
    }
}

enum EventItemKind: Hashable {
    case click, impression, purchase, pageview, render
}

extension [EventItem] {
    func toEvents() -> Events {
        var impressions: [Event] = []
        var clicks: [Event] = []
        var purchases: [PurchaseEvent] = []
        var pageviews: [PageViewEvent] = []
        var renders: [RenderEvent] = []
        for item in self {
            switch item {
            case let .impression(event): impressions.append(event)
            case let .click(event): clicks.append(event)
            case let .purchase(event): purchases.append(event)
            case let .pageview(event): pageviews.append(event)
            case let .render(event): renders.append(event)
            }
        }
        return Events(
            impressions: impressions.isEmpty ? nil : impressions,
            clicks: clicks.isEmpty ? nil : clicks,
            purchases: purchases.isEmpty ? nil : purchases,
            pageviews: pageviews.isEmpty ? nil : pageviews,
            renders: renders.isEmpty ? nil : renders
        )
    }
}

extension Events {
    func toItems() -> [EventItem] {
        var items: [EventItem] = []
        items += (impressions ?? []).map { .impression($0) }
        items += (clicks ?? []).map { .click($0) }
        items += (purchases ?? []).map { .purchase($0) }
        items += (pageviews ?? []).map { .pageview($0) }
        items += (renders ?? []).map { .render($0) }
        return items
    }
}

struct PendingEvents: Codable {
    let id: UUID
    let data: Data
    let createdAt: Date
    var retries: Int
    var lastRetry: Date
    /// How many events the stored body carries; the body is the only record of them.
    var eventCount: Int {
        guard let events = try? JSONDecoder().decode(Events.self, from: data) else { return 0 }
        // Written as statements: the one-line sum of four optionals times out Xcode 16's type checker.
        var count = events.impressions?.count ?? 0
        count += events.clicks?.count ?? 0
        count += events.purchases?.count ?? 0
        count += events.pageviews?.count ?? 0
        count += events.renders?.count ?? 0
        return count
    }

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
/// The API rejects a request whose renders/impressions/clicks/purchases/pageviews array
/// exceeds this many items with a non-retriable 400 — discarding every event type bundled
/// into that request, not just the type that went over. No single type may exceed it in one
/// outgoing batch; events past the cap stay queued for the next one.
let MAX_EVENTS_PER_TYPE_PER_BATCH = 50
