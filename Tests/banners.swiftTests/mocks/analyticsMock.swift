import Foundation
@testable import Topsort
import XCTest

public class MockTopsort: TopsortProtocol {
    public var opaqueUserId: String = "mocked-opaque-user-id"
    public var isConfigured: Bool = true
    public var executeAuctionsMockResponse: AuctionResponse

    public var trackedImpressions: [Event] = []
    public var trackedClicks: [Event] = []
    public var trackedPurchases: [PurchaseEvent] = []

    public init(executeAuctionsMockResponse: AuctionResponse) {
        self.executeAuctionsMockResponse = executeAuctionsMockResponse
    }

    public func set(opaqueUserId _: String?) {
        // Mock implementation
    }

    public func configure(apiKey _: String, url _: String?, auctionsTimeout _: TimeInterval?) throws {
        // Mock implementation
    }

    public func track(impression event: Event) {
        trackedImpressions.append(event)
    }

    public func track(click event: Event) {
        trackedClicks.append(event)
    }

    public func track(purchase event: PurchaseEvent) {
        trackedPurchases.append(event)
    }

    public func executeAuctions(auctions _: [Auction]) async throws(AuctionError) -> AuctionResponse {
        return executeAuctionsMockResponse
    }
}
