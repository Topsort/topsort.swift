import Foundation
import XCTest
@testable import Topsort_Analytics

public class MockAnalytics: AnalyticsProtocol {
    public var opaqueUserId: String = "mocked-opaque-user-id"
    public var executeAuctionsMockResponse: AuctionResponse?

    public func set(opaqueUserId: String?) {
        // Mock implementation
    }

    public func configure(apiKey: String, url: String? = nil) {
        // Mock implementation
    }

    public func track(impression event: Event) {
        // Mock implementation
    }

    public func track(click event: Event) {
        // Mock implementation
    }

    public func track(purchase event: PurchaseEvent) {
        // Mock implementation
    }

    public func executeAuctions(auctions: [Auction]) async -> AuctionResponse? {
        return executeAuctionsMockResponse
    }
}
