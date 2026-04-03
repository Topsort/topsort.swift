/*
 Topsort Events API models based on our public API: https://docs.topsort.com/reference/reportevents-2
 */

import Foundation

public enum EntityType: String, Codable {
    case product
    case vendor
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
    /// The type of page (e.g. "category", "product", "search", "home").
    let type: String
    /// An identifier for the page.
    let pageId: String?
    /// A value associated with the page (e.g. category name, search query).
    let value: String?

    public init(type: String, pageId: String? = nil, value: String? = nil) {
        self.type = type
        self.pageId = pageId
        self.value = value
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
    let id: UUID

    /**
     If the impression is over an ad promotion, this is the `resolvedBidId` field received from the /auctions request.
     */
    let resolvedBidId: String?

    let placement: Placement?

    /// Device type: "desktop" or "mobile".
    let deviceType: String?

    /// Channel: "onsite", "offsite", or "instore".
    let channel: String?

    /// Additional entity for halo attribution. Requires resolvedBidId to be set.
    let additionalAttribution: Entity?

    /// Click type: "product", "like", or "add-to-cart". Only applicable for click events.
    let clickType: String?

    public init(
        entity: Entity,
        occurredAt: Date,
        opaqueUserId: String = Topsort.shared.opaqueUserId,
        placement: Placement? = nil,
        deviceType: String? = nil,
        channel: String? = nil,
        additionalAttribution: Entity? = nil,
        clickType: String? = nil
    ) {
        self.entity = entity
        self.occurredAt = occurredAt
        self.opaqueUserId = opaqueUserId
        resolvedBidId = nil
        self.placement = placement
        self.deviceType = deviceType
        self.channel = channel
        self.additionalAttribution = additionalAttribution
        self.clickType = clickType
        id = UUID()
    }

    public init(
        resolvedBidId: String,
        occurredAt: Date,
        opaqueUserId: String = Topsort.shared.opaqueUserId,
        placement: Placement? = nil,
        deviceType: String? = nil,
        channel: String? = nil,
        additionalAttribution: Entity? = nil,
        clickType: String? = nil
    ) {
        entity = nil
        self.occurredAt = occurredAt
        self.opaqueUserId = opaqueUserId
        self.resolvedBidId = resolvedBidId
        self.placement = placement
        self.deviceType = deviceType
        self.channel = channel
        self.additionalAttribution = additionalAttribution
        self.clickType = clickType
        id = UUID()
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
    let id: UUID

    /// Device type: "desktop" or "mobile".
    let deviceType: String?

    /// Channel: "onsite", "offsite", or "instore".
    let channel: String?

    public init(
        items: [PurchaseItem],
        occurredAt: Date,
        opaqueUserId: String = Topsort.shared.opaqueUserId,
        deviceType: String? = nil,
        channel: String? = nil
    ) {
        self.items = items
        self.occurredAt = occurredAt
        self.opaqueUserId = opaqueUserId
        self.deviceType = deviceType
        self.channel = channel
        id = UUID()
    }
}

/// A page view event for tracking navigation.
public struct PageViewEvent: Codable {
    @TSDateValue
    var occurredAt: Date
    let opaqueUserId: String
    let id: UUID
    let page: Page

    /// Device type: "desktop" or "mobile".
    let deviceType: String?

    /// Channel: "onsite", "offsite", or "instore".
    let channel: String?

    public init(
        page: Page,
        occurredAt: Date,
        opaqueUserId: String = Topsort.shared.opaqueUserId,
        deviceType: String? = nil,
        channel: String? = nil
    ) {
        self.page = page
        self.occurredAt = occurredAt
        self.opaqueUserId = opaqueUserId
        self.deviceType = deviceType
        self.channel = channel
        id = UUID()
    }
}

struct Events: Codable {
    let impressions: [Event]?
    let clicks: [Event]?
    let purchases: [PurchaseEvent]?
    let pageviews: [PageViewEvent]?

    init(impressions: [Event], clicks: [Event]? = nil, purchases: [PurchaseEvent]? = nil, pageviews: [PageViewEvent]? = nil) {
        self.impressions = impressions
        self.clicks = clicks
        self.purchases = purchases
        self.pageviews = pageviews
    }

    init(clicks: [Event], impressions: [Event]? = nil, purchases: [PurchaseEvent]? = nil, pageviews: [PageViewEvent]? = nil) {
        self.impressions = impressions
        self.clicks = clicks
        self.purchases = purchases
        self.pageviews = pageviews
    }

    init(purchases: [PurchaseEvent], impressions: [Event]? = nil, clicks: [Event]? = nil, pageviews: [PageViewEvent]? = nil) {
        self.impressions = impressions
        self.clicks = clicks
        self.purchases = purchases
        self.pageviews = pageviews
    }

    init(pageviews: [PageViewEvent], impressions: [Event]? = nil, clicks: [Event]? = nil, purchases: [PurchaseEvent]? = nil) {
        self.impressions = impressions
        self.clicks = clicks
        self.purchases = purchases
        self.pageviews = pageviews
    }
}
