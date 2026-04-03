@testable import Topsort
@testable import TopsortBanners
import XCTest

class TopsortBannerTests: XCTestCase {
    func testTopsortBannerInitialization() throws {
        var config = Configuration(apiKey: "test_api_key")
        config.url = "test_url"
        try Topsort.shared.configure(config)
        let expectation = self.expectation(description: "Button clicked action")
        let banner = TopsortBanner(bannerAuctionBuilder: .init(
            slotId: "test_slot_id",
            deviceType: "test_device_type"
        )).buttonClickedAction { _ in
            expectation.fulfill()
        }

        banner.buttonClickedAction?(nil)

        wait(for: [expectation], timeout: 1.0)
    }

    func testExecuteAuctions() async throws {
        // Mock the response
        let asset = Asset(url: "https://example.com")
        let winner = Winner(rank: 1, asset: [asset], type: "type", id: "id", resolvedBidId: "resolved_bid_id")
        let auctionResult = AuctionResult(resultType: "result_type", winners: [winner], error: false)
        let auctionResponse = AuctionResponse(results: [auctionResult])

        // Mock Topsort and response
        let mockTopsort = MockTopsort(executeAuctionsMockResponse: auctionResponse)
        var config = Configuration(apiKey: "test_api_key")
        config.url = "test_url"
        try Topsort.shared.configure(config)

        let auction = BannerAuctionBuilder(
            slotId: "test_slot_id",
            deviceType: "test_device_type"
        ).build()

        let vm = await TopsortBanner.ViewModel()

        await vm.executeAuctions(auction: auction, topsort: mockTopsort, onError: nil, onNoWinners: nil)

        await MainActor.run {
            XCTAssertEqual(vm.resolvedBidId, "resolved_bid_id")
            XCTAssertEqual(vm.urlString, "https://example.com")
            XCTAssertFalse(vm.loading)
        }
    }

    func testExecuteAuctionsDoesNotTrackImpression() async throws {
        let asset = Asset(url: "https://example.com")
        let winner = Winner(rank: 1, asset: [asset], type: "type", id: "id", resolvedBidId: "bid-id")
        let auctionResult = AuctionResult(resultType: "result_type", winners: [winner], error: false)
        let auctionResponse = AuctionResponse(results: [auctionResult])

        let mockTopsort = MockTopsort(executeAuctionsMockResponse: auctionResponse)
        var config = Configuration(apiKey: "test_api_key")
        config.url = "test_url"
        try Topsort.shared.configure(config)

        let auction = BannerAuctionBuilder(
            slotId: "test_slot_id",
            deviceType: "test_device_type"
        ).build()

        let vm = await TopsortBanner.ViewModel()
        await vm.executeAuctions(auction: auction, topsort: mockTopsort, onError: nil, onNoWinners: nil)

        // Impression should NOT be tracked during executeAuctions
        // It should only be tracked when the image loads (onSuccess)
        XCTAssertTrue(mockTopsort.trackedImpressions.isEmpty, "Impression should not be tracked on auction response — only on image load")
    }

    func testExecuteAuctionsCallsOnNoWinners() async throws {
        let auctionResult = AuctionResult(resultType: "result_type", winners: [], error: false)
        let auctionResponse = AuctionResponse(results: [auctionResult])

        let mockTopsort = MockTopsort(executeAuctionsMockResponse: auctionResponse)
        var config = Configuration(apiKey: "test_api_key")
        config.url = "test_url"
        try Topsort.shared.configure(config)

        let auction = BannerAuctionBuilder(
            slotId: "test_slot_id",
            deviceType: "test_device_type"
        ).build()

        var noWinnersCalled = false
        let vm = await TopsortBanner.ViewModel()
        await vm.executeAuctions(auction: auction, topsort: mockTopsort, onError: nil, onNoWinners: { noWinnersCalled = true })

        XCTAssertTrue(noWinnersCalled)
        await MainActor.run {
            XCTAssertNil(vm.resolvedBidId)
            XCTAssertNil(vm.urlString)
        }
    }

    func testExecuteAuctionsCallsOnError() async throws {
        let failingMock = FailingMockTopsort()
        var config = Configuration(apiKey: "test_api_key")
        config.url = "test_url"
        try Topsort.shared.configure(config)

        let auction = BannerAuctionBuilder(
            slotId: "test_slot_id",
            deviceType: "test_device_type"
        ).build()

        var errorReceived: BannerError?
        let vm = await TopsortBanner.ViewModel()
        await vm.executeAuctions(auction: auction, topsort: failingMock, onError: { error in errorReceived = error }, onNoWinners: nil)

        XCTAssertNotNil(errorReceived)
    }
}

private class FailingMockTopsort: TopsortProtocol {
    var opaqueUserId: String = "test"
    var isConfigured: Bool = true
    func set(opaqueUserId _: String?) {}
    func configure(_: Configuration) throws {}
    func track(impression _: Event) {}
    func track(click _: Event) {}
    func track(purchase _: PurchaseEvent) {}
    func executeAuctions(auctions _: [Auction]) async throws(AuctionError) -> AuctionResponse {
        throw .emptyResponse
    }
}
