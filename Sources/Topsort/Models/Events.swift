/*
 Topsort Events API models based on our public API: https://docs.topsort.com/reference/reportevents-2
 */

import Foundation

public enum EntityType: String, Codable {
    case product
    case vendor
}

/// The device the user is on.
public enum DeviceType: String, Codable, Sendable {
    case desktop
    case mobile
}

/// Where the event occurred.
public enum Channel: String, Codable, Sendable {
    case onsite
    case offsite
    case instore
}

/// The specific flavor of a click on a sponsored listing.
public enum ClickType: String, Codable, Sendable {
    case product
    case like
    case addToCart = "add-to-cart"
}

/// The type of page an event or auction occurred on.
public enum PageType: String, Codable, Sendable {
    case home
    case category
    /// Product detail page.
    case pdp = "PDP"
    case search
    case cart
    case other
}

public struct Placement: Codable {
    /**
     URL path of the page triggering the event.

     For mobile apps, use the deep link for the current view, if available.
     Otherwise, encode the view from which the event occurred in your app as a path-like string (e.g. /root/categories/:categoryId).
     */
    let path: String

    /**
     For components with multiple items (i.e. search results, similar products, etc), this should indicate the index of a given item within that list.
     */
    let position: Int?

    /**
     For paginated pages, this should indicate which page number triggered the event.
     */
    let page: Int?

    /**
     For paginated pages this should indicate how many items are in each result page.
     */
    let pageSize: Int?

    /**
     The ID of the product associated to the page in which this event occurred, if applicable. This ID must match the ID
     provided through the catalog service.
     */
    let productId: String?

    /**
     An array of IDs of the categories associated to the page in which this event occurred, if applicable. These IDs must
     match the IDs provided through the catalog service.
     */
    let categoryIds: [String]?

    /**
     The search string provided by the user in the page where this event occurred, if applicable. This search string must
     match the searchQuery field that was provided in the auction request (if provided).
     */
    let searchQuery: String?

    public init(path: String, position: Int? = nil, page: Int? = nil, pageSize: Int? = nil, productId: String? = nil, categoryIds: [String]? = nil, searchQuery: String? = nil) {
        self.path = path
        self.position = position
        self.page = page
        self.pageSize = pageSize
        self.productId = productId
        self.categoryIds = categoryIds
        self.searchQuery = searchQuery
    }
}

public struct Entity: Codable {
    let type: EntityType
    let id: String

    public init(type: EntityType, id: String) {
        self.type = type
        self.id = id
    }
}

/// Page context for pageview events and auction requests.
public struct Page: Codable {
    /// The type of page.
    public let type: PageType
    /// An identifier for the page (required by the API).
    public let pageId: String
    /// A single value (e.g. category name, search query) or an array of values
    /// (e.g. product IDs for cart pages). The API accepts either format under the `value` key.
    public let value: PageValue?

    public init(type: PageType, pageId: String, value: String? = nil) {
        self.type = type
        self.pageId = pageId
        self.value = value.map { .string($0) }
    }

    /// An array value is only valid for `.cart` (the items in the cart), and must not be empty.
    public init(type: PageType, pageId: String, values: [String]) {
        self.type = type
        self.pageId = pageId
        value = .array(values)
    }
}

/// A page value that can be either a single string or an array of strings.
public enum PageValue: Codable {
    case string(String)
    case array([String])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let arr = try? container.decode([String].self) {
            self = .array(arr)
        } else {
            throw DecodingError.typeMismatch(PageValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected String or [String]"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(s): try container.encode(s)
        case let .array(arr): try container.encode(arr)
        }
    }

    /// Convenience: get the string value (nil if array).
    public var stringValue: String? {
        if case let .string(s) = self {
            return s
        }
        return nil
    }

    /// Convenience: get the array value (nil if string).
    public var arrayValue: [String]? {
        if case let .array(arr) = self {
            return arr
        }
        return nil
    }
}

public struct Event: Codable {
    /**
     The entity associated with the promotable over which the interaction occurred.
     It will be ignored if resolvedBidId is not blank.
     */
    let entity: Entity?

    /**
     RFC3339 formatted timestamp including UTC offset.
     */
    @TSDateValue
    var occurredAt: Date

    /**
     The opaque user ID allows correlating user activity, such as Impressions, Clicks and Purchases, whether or not they
     are actually logged in. It must be long lived (at least a year) so that Topsort can attribute purchases.
     */
    let opaqueUserId: String

    /**
     The marketplace's unique ID for the impression. This field ensures the event reporting is idempotent in case there is
     a network issue and the request is retried.
     */
    let id: String

    /**
     If the impression is over an ad promotion, this is the `resolvedBidId` field received from the /auctions request.
     */
    let resolvedBidId: String?

    let placement: Placement?

    /// Page context for the event.
    let page: Page?

    let deviceType: DeviceType?

    let channel: Channel?

    /// Additional entity for halo attribution. Requires resolvedBidId to be set.
    let additionalAttribution: Entity?

    /// Only applicable for click events.
    let clickType: ClickType?

    public init(
        entity: Entity,
        occurredAt: Date,
        opaqueUserId: String = Topsort.shared.opaqueUserId,
        placement: Placement? = nil,
        page: Page? = nil,
        deviceType: DeviceType? = nil,
        channel: Channel? = nil,
        additionalAttribution: Entity? = nil,
        clickType: ClickType? = nil,
        id: String = UUID().uuidString
    ) {
        self.entity = entity
        self.occurredAt = occurredAt
        self.opaqueUserId = opaqueUserId
        resolvedBidId = nil
        self.placement = placement
        self.page = page
        self.deviceType = deviceType
        self.channel = channel
        self.additionalAttribution = additionalAttribution
        self.clickType = clickType
        self.id = id
    }

    public init(
        resolvedBidId: String,
        occurredAt: Date,
        opaqueUserId: String = Topsort.shared.opaqueUserId,
        placement: Placement? = nil,
        page: Page? = nil,
        deviceType: DeviceType? = nil,
        channel: Channel? = nil,
        additionalAttribution: Entity? = nil,
        clickType: ClickType? = nil,
        id: String = UUID().uuidString
    ) {
        entity = nil
        self.occurredAt = occurredAt
        self.opaqueUserId = opaqueUserId
        self.resolvedBidId = resolvedBidId
        self.placement = placement
        self.page = page
        self.deviceType = deviceType
        self.channel = channel
        self.additionalAttribution = additionalAttribution
        self.clickType = clickType
        self.id = id
    }
}

/// A render means an ad was inserted into the page (IAB "rendered"), reported separately from
/// when it becomes visible (an impression). Renders are sponsored-only, so `resolvedBidId` is required.
public struct RenderEvent: Codable {
    /**
     The `resolvedBidId` field received from the `/auctions` request.
     */
    let resolvedBidId: String

    /**
     RFC3339 formatted timestamp including UTC offset.
     */
    @TSDateValue
    var occurredAt: Date

    /**
     The opaque user ID allows correlating user activity, such as Renders, Impressions, Clicks and Purchases, whether or not they
     are actually logged in. It must be long lived (at least a year) so that Topsort can attribute purchases.
     */
    let opaqueUserId: String

    /**
     The marketplace's unique ID for the render. This field ensures the event reporting is idempotent in case there is
     a network issue and the request is retried.
     */
    let id: String

    let placement: Placement?

    /// Page context for the event.
    let page: Page?

    let deviceType: DeviceType?

    let channel: Channel?

    public init(
        resolvedBidId: String,
        occurredAt: Date,
        opaqueUserId: String = Topsort.shared.opaqueUserId,
        placement: Placement? = nil,
        page: Page? = nil,
        deviceType: DeviceType? = nil,
        channel: Channel? = nil,
        id: String = UUID().uuidString
    ) {
        self.resolvedBidId = resolvedBidId
        self.occurredAt = occurredAt
        self.opaqueUserId = opaqueUserId
        self.placement = placement
        self.page = page
        self.deviceType = deviceType
        self.channel = channel
        self.id = id
    }
}

/// A VAST playback checkpoint reached by a sponsored video ad.
public enum VideoCheckpoint: String, Codable, Sendable {
    /// Playback started.
    case start
    /// Playback reached 25% of the video's duration.
    case firstQuartile
    /// Playback reached 50% of the video's duration.
    case midpoint
    /// Playback reached 75% of the video's duration.
    case thirdQuartile
    /// Playback reached the end of the video.
    case complete
}

/// A video event reports that a sponsored video ad reached a playback checkpoint or failed to play.
/// Event names follow the IAB VAST tracking-event vocabulary. Video events are sponsored-only, so
/// `resolvedBidId` is required and must come from a video campaign (the API rejects any other bid).
/// They feed engagement and delivery reporting only and are never charged or attributed.
public struct VideoEvent: Codable {
    /**
     The `resolvedBidId` field received from the `/auctions` request for a video ad.
     */
    let resolvedBidId: String

    /**
     One of `start`, `firstQuartile`, `midpoint`, `thirdQuartile`, `complete` or `error`. Set by the
     initializer: a `VideoCheckpoint` for playback, `error` when built with an `errorCode`.
     */
    let eventType: String

    /**
     VAST error code describing why the video failed (e.g. `405`). Present only when `eventType` is `error`,
     where the API requires it. `Int32` because the API takes any int32: a wider value would fail to decode
     server side and reject the whole request.
     */
    let errorCode: Int32?

    /**
     RFC3339 formatted timestamp including UTC offset.
     */
    @TSDateValue
    var occurredAt: Date

    /**
     The opaque user ID allows correlating user activity, such as Video events, Impressions, Clicks and Purchases, whether or not they
     are actually logged in. It must be long lived (at least a year) so that Topsort can attribute purchases.
     */
    let opaqueUserId: String

    /**
     The marketplace's unique ID for the video event. This field ensures the event reporting is idempotent in case there is
     a network issue and the request is retried.
     */
    let id: String

    let placement: Placement?

    /// Page context for the event.
    let page: Page?

    let deviceType: DeviceType?

    let channel: Channel?

    /// Reports that playback reached `checkpoint`.
    public init(
        resolvedBidId: String,
        checkpoint: VideoCheckpoint,
        occurredAt: Date,
        opaqueUserId: String = Topsort.shared.opaqueUserId,
        placement: Placement? = nil,
        page: Page? = nil,
        deviceType: DeviceType? = nil,
        channel: Channel? = nil,
        id: String = UUID().uuidString
    ) {
        self.init(
            resolvedBidId: resolvedBidId, eventType: checkpoint.rawValue, errorCode: nil, occurredAt: occurredAt,
            opaqueUserId: opaqueUserId, placement: placement, page: page, deviceType: deviceType, channel: channel, id: id
        )
    }

    /// Reports that the video could not be delivered or played, with the VAST `errorCode` the player raised.
    public init(
        resolvedBidId: String,
        errorCode: Int32,
        occurredAt: Date,
        opaqueUserId: String = Topsort.shared.opaqueUserId,
        placement: Placement? = nil,
        page: Page? = nil,
        deviceType: DeviceType? = nil,
        channel: Channel? = nil,
        id: String = UUID().uuidString
    ) {
        self.init(
            resolvedBidId: resolvedBidId, eventType: "error", errorCode: errorCode, occurredAt: occurredAt,
            opaqueUserId: opaqueUserId, placement: placement, page: page, deviceType: deviceType, channel: channel, id: id
        )
    }

    private init(
        resolvedBidId: String,
        eventType: String,
        errorCode: Int32?,
        occurredAt: Date,
        opaqueUserId: String,
        placement: Placement?,
        page: Page?,
        deviceType: DeviceType?,
        channel: Channel?,
        id: String
    ) {
        self.resolvedBidId = resolvedBidId
        self.eventType = eventType
        self.errorCode = errorCode
        self.occurredAt = occurredAt
        self.opaqueUserId = opaqueUserId
        self.placement = placement
        self.page = page
        self.deviceType = deviceType
        self.channel = channel
        self.id = id
    }
}

public struct PurchaseItem: Codable {
    /// The marketplace ID of the product being purchased.
    let productId: String

    /// Count of products purchased.
    let quantity: Int?

    /// The price of a single item in the marketplace currency.
    let unitPrice: Double

    /// The vendor ID for halo attribution.
    let vendorId: String?

    public init(productId: String, unitPrice: Double, quantity: Int? = nil, vendorId: String? = nil) {
        self.productId = productId
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.vendorId = vendorId
    }
}

public struct PurchaseEvent: Codable {
    /**
     RFC3339 formatted timestamp, including UTC offset, of the instant in which the order was placed.
     */
    @TSDateValue
    var occurredAt: Date

    /**
     The opaque user ID allows correlating user activity.
     */
    let opaqueUserId: String

    let items: [PurchaseItem]

    /**
     The marketplace unique ID for the order. Ensures idempotent event reporting.
     */
    let id: String

    let deviceType: DeviceType?

    let channel: Channel?

    public init(
        items: [PurchaseItem],
        occurredAt: Date,
        opaqueUserId: String = Topsort.shared.opaqueUserId,
        deviceType: DeviceType? = nil,
        channel: Channel? = nil,
        id: String = UUID().uuidString
    ) {
        self.items = items
        self.occurredAt = occurredAt
        self.opaqueUserId = opaqueUserId
        self.deviceType = deviceType
        self.channel = channel
        self.id = id
    }
}

/// A page view event for tracking navigation.
public struct PageViewEvent: Codable {
    @TSDateValue
    var occurredAt: Date
    let opaqueUserId: String
    /// The marketplace's unique ID for the page view; the API dedups on it.
    let id: String
    let page: Page

    let deviceType: DeviceType?

    let channel: Channel?

    public init(
        page: Page,
        occurredAt: Date,
        opaqueUserId: String = Topsort.shared.opaqueUserId,
        deviceType: DeviceType? = nil,
        channel: Channel? = nil,
        id: String = UUID().uuidString
    ) {
        self.page = page
        self.occurredAt = occurredAt
        self.opaqueUserId = opaqueUserId
        self.deviceType = deviceType
        self.channel = channel
        self.id = id
    }
}

struct Events: Codable {
    let impressions: [Event]?
    let clicks: [Event]?
    let purchases: [PurchaseEvent]?
    let pageviews: [PageViewEvent]?
    let renders: [RenderEvent]?
    let videoEvents: [VideoEvent]?

    init(impressions: [Event]? = nil, clicks: [Event]? = nil, purchases: [PurchaseEvent]? = nil, pageviews: [PageViewEvent]? = nil, renders: [RenderEvent]? = nil, videoEvents: [VideoEvent]? = nil) {
        self.impressions = impressions
        self.clicks = clicks
        self.purchases = purchases
        self.pageviews = pageviews
        self.renders = renders
        self.videoEvents = videoEvents
    }

    init(impressions: [Event], clicks: [Event]? = nil, purchases: [PurchaseEvent]? = nil, pageviews: [PageViewEvent]? = nil, renders: [RenderEvent]? = nil, videoEvents: [VideoEvent]? = nil) {
        self.impressions = impressions
        self.clicks = clicks
        self.purchases = purchases
        self.pageviews = pageviews
        self.renders = renders
        self.videoEvents = videoEvents
    }

    init(clicks: [Event], impressions: [Event]? = nil, purchases: [PurchaseEvent]? = nil, pageviews: [PageViewEvent]? = nil, renders: [RenderEvent]? = nil, videoEvents: [VideoEvent]? = nil) {
        self.impressions = impressions
        self.clicks = clicks
        self.purchases = purchases
        self.pageviews = pageviews
        self.renders = renders
        self.videoEvents = videoEvents
    }

    init(purchases: [PurchaseEvent], impressions: [Event]? = nil, clicks: [Event]? = nil, pageviews: [PageViewEvent]? = nil, renders: [RenderEvent]? = nil, videoEvents: [VideoEvent]? = nil) {
        self.impressions = impressions
        self.clicks = clicks
        self.purchases = purchases
        self.pageviews = pageviews
        self.renders = renders
        self.videoEvents = videoEvents
    }

    init(pageviews: [PageViewEvent], impressions: [Event]? = nil, clicks: [Event]? = nil, purchases: [PurchaseEvent]? = nil, renders: [RenderEvent]? = nil, videoEvents: [VideoEvent]? = nil) {
        self.impressions = impressions
        self.clicks = clicks
        self.purchases = purchases
        self.pageviews = pageviews
        self.renders = renders
        self.videoEvents = videoEvents
    }

    init(renders: [RenderEvent], impressions: [Event]? = nil, clicks: [Event]? = nil, purchases: [PurchaseEvent]? = nil, pageviews: [PageViewEvent]? = nil, videoEvents: [VideoEvent]? = nil) {
        self.impressions = impressions
        self.clicks = clicks
        self.purchases = purchases
        self.pageviews = pageviews
        self.renders = renders
        self.videoEvents = videoEvents
    }

    init(videoEvents: [VideoEvent], impressions: [Event]? = nil, clicks: [Event]? = nil, purchases: [PurchaseEvent]? = nil, pageviews: [PageViewEvent]? = nil, renders: [RenderEvent]? = nil) {
        self.impressions = impressions
        self.clicks = clicks
        self.purchases = purchases
        self.pageviews = pageviews
        self.renders = renders
        self.videoEvents = videoEvents
    }
}

// MARK: - Spec rules the types cannot express

/// The events API rejects a whole request, with a non-retriable 400, when any one event in it
/// breaks the spec. These are the rules the Swift types do not already enforce; an event that
/// breaks one is dropped on its own, before it can take its batch down with it.
protocol SpecValidated {
    /// A description of the first rule this value breaks, or nil when it is valid.
    var specViolation: String? { get }
}

extension Placement: SpecValidated {
    var specViolation: String? {
        if path.isEmpty {
            return "placement.path is empty"
        }
        if let position, position < 1 {
            return "placement.position \(position) is below 1"
        }
        if let page, page < 1 {
            return "placement.page \(page) is below 1"
        }
        if let pageSize, pageSize < 1 {
            return "placement.pageSize \(pageSize) is below 1"
        }
        if productId?.isEmpty == true {
            return "placement.productId is empty"
        }
        if categoryIds?.isEmpty == true {
            return "placement.categoryIds is empty"
        }
        if searchQuery?.isEmpty == true {
            return "placement.searchQuery is empty"
        }
        return nil
    }
}

extension Page: SpecValidated {
    var specViolation: String? {
        if value?.arrayValue?.isEmpty == true {
            return "page.value is an empty array"
        }
        return nil
    }
}

/// The checks every event shares: a non-empty `id` (the API dedupes on it) and valid context.
private func contextViolation(id: String, placement: Placement?, page: Page?) -> String? {
    if id.isEmpty {
        return "id is empty"
    }
    return placement?.specViolation ?? page?.specViolation
}

extension Event: SpecValidated {
    var specViolation: String? {
        contextViolation(id: id, placement: placement, page: page)
    }
}

extension RenderEvent: SpecValidated {
    var specViolation: String? {
        contextViolation(id: id, placement: placement, page: page)
    }
}

extension VideoEvent: SpecValidated {
    var specViolation: String? {
        contextViolation(id: id, placement: placement, page: page)
    }
}

extension PurchaseEvent: SpecValidated {
    var specViolation: String? {
        contextViolation(id: id, placement: nil, page: nil)
    }
}

extension PageViewEvent: SpecValidated {
    var specViolation: String? {
        contextViolation(id: id, placement: nil, page: page)
    }
}
