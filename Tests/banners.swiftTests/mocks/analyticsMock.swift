import Foundation
@testable import Topsort
import XCTest

public class MockTopsort: TopsortProtocol {
    public var opaqueUserId: String = "mocked-opaque-user-id"
    public var executeAuctionsMockResponse: AuctionResponse
    
    public init(executeAuctionsMockResponse: AuctionResponse) {
        self.executeAuctionsMockResponse = executeAuctionsMockResponse
    }

    public func set(opaqueUserId _: String?) {
        // Mock implementation
    }

    public func configure(apiKey: String, url: String?, auctionsTimeout: TimeInterval?) {
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

    public func executeAuctions(auctions: [Auction]) async throws(AuctionError) -> AuctionResponse {
        return executeAuctionsMockResponse
    }
}
