import Foundation
@testable import Topsort
import XCTest

public class MockTopsort: TopsortProtocol {
    public var opaqueUserId: String = "mocked-opaque-user-id"
    public var executeAuctionsMockResponse: AuctionResponse?

    public func set(opaqueUserId _: String?) {
        // Mock implementation
    }

    public func configure(apiKey _: String, url _: String? = nil) {
        // Mock implementation
    }

    public func track(impression _: Event) {
        // Mock implementation
    }

    public func track(click _: Event) {
        // Mock implementation
    }

    public func track(purchase _: PurchaseEvent) {
        // Mock implementation
    }

    public func executeAuctions(auctions _: [Auction]) async -> AuctionResponse? {
        return executeAuctionsMockResponse
    }
}
