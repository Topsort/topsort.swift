import Foundation

// Auctions requests models

public struct AuctionGeoTargeting: Codable {
    /**
     * The location this auction is being run for.
     */
    let location: String

    public init(location: String) {
        self.location = location
    }
}

public struct AuctionCategory: Codable {
    /**
     * The category ID of the bids that will participate in an auction.
     */
    let id: String?

    /**
     * An array containing the category IDs of the bids that will participate in an auction.
     * In order to participate in an auction, a bid product must belong to all of the categories provided in the auction request.
     */
    let ids: [String]?

    /**
     * An array of disjunctions.
     * In order to participate in an auction, a bid product must belong to at least one of the categories for each of the disjunctions provided in the auction request.
     */
    let disjunctions: [String]?

    public init(id: String? = nil, ids: [String]? = nil, disjunctions: [String]? = nil) {
        self.id = id
        self.ids = ids
        self.disjunctions = disjunctions
    }
}

public struct AuctionProducts: Codable {
    /**
     * The list of product IDs to be considered in the auction.
     */
    let ids: [String]

    /**
     * The list of quality scores for the products in the auction.
     */
    let qualityScores: [Double]?

    public init(ids: [String], qualityScores: [Double]? = nil) {
        if qualityScores != nil && ids.count != qualityScores!.count {
            fatalError("The number of quality scores must match the number of product IDs.")
        }
        self.ids = ids
        self.qualityScores = qualityScores
    }
}

public struct Auction: Codable {
    /**
     * Discriminator for the type of auction.
     * Could be one of the following values:
     * - "listings"
     * - "banner"
     */
    let type: String

    /**
     * Specifies the maximum number of auction winners that should be returned.
     */
    let slots: Int

    /**
     * The ID of the banner placement for which this auction will be run for.
     */
    let slotId: String?

    /**
     * Discriminator for the device type.
     * - "desktop"
     * - "mobile"
     */
    let device: String?
    let products: AuctionProducts?
    let category: AuctionCategory?

    /**
     * The search string provided by a user.
     */
    let searchQuery: String?
    let geoTargeting: AuctionGeoTargeting?

    public init(
        type: String,
        slots: Int,
        slotId: String? = nil,
        device: String? = nil,
        products: AuctionProducts? = nil,
        category: AuctionCategory? = nil,
        searchQuery: String? = nil,
        geoTargeting: AuctionGeoTargeting? = nil
    ) {
        self.type = type
        self.slots = slots
        self.slotId = slotId
        self.device = device
        self.geoTargeting = geoTargeting
        self.searchQuery = searchQuery
        self.category = category
        self.products = products
    }
}

// Auctions response models

public struct Asset: Codable {
    public let url: String
}

public struct Winner: Codable {
    public let rank: Int
    public let asset: [Asset]?
    public let type: String
    public let id: String
    public let resolvedBidId: String
}

public struct AuctionResult: Codable {
    public let resultType: String
    public let winners: [Winner]
    public let error: Bool
}

public struct AuctionResponse: Codable {
    public let results: [AuctionResult]
}
