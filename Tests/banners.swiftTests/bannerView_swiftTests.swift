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
        let asset = Asset(url: "https://example.com", content: nil)
        let winner = Winner(rank: 1, asset: [asset], type: "type", id: "id", resolvedBidId: "resolved_bid_id", campaignId: nil)
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
        let asset = Asset(url: "https://example.com", content: nil)
        let winner = Winner(rank: 1, asset: [asset], type: "type", id: "id", resolvedBidId: "bid-id", campaignId: nil)
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

    // MARK: - BannerAuctionBuilder

    func testBannerAuctionBuilderBuild() {
        let builder = BannerAuctionBuilder(slotId: "home", deviceType: "mobile")
        let auction = builder.build()
        XCTAssertEqual(auction.type, "banners")
        XCTAssertEqual(auction.slots, 1)
        XCTAssertEqual(auction.slotId, "home")
        XCTAssertEqual(auction.device, "mobile")
        XCTAssertNil(auction.products)
        XCTAssertNil(auction.category)
        XCTAssertNil(auction.searchQuery)
        XCTAssertNil(auction.geoTargeting)
    }

    func testBannerAuctionBuilderWithProducts() throws {
        let products = try AuctionProducts(ids: ["p1", "p2"])
        let builder = BannerAuctionBuilder(slotId: "s1", deviceType: "desktop")
            .with(products: products)
        let auction = builder.build()
        XCTAssertEqual(auction.products?.ids, ["p1", "p2"])
    }

    func testBannerAuctionBuilderWithCategory() {
        let category = AuctionCategory(id: "c1")
        let builder = BannerAuctionBuilder(slotId: "s1", deviceType: "mobile")
            .with(category: category)
        let auction = builder.build()
        XCTAssertEqual(auction.category?.id, "c1")
    }

    func testBannerAuctionBuilderWithSearchQuery() {
        let builder = BannerAuctionBuilder(slotId: "s1", deviceType: "mobile")
            .with(searchQuery: "shoes")
        let auction = builder.build()
        XCTAssertEqual(auction.searchQuery, "shoes")
    }

    func testBannerAuctionBuilderWithGeoTargeting() {
        let geo = AuctionGeoTargeting(location: "US")
        let builder = BannerAuctionBuilder(slotId: "s1", deviceType: "mobile")
            .with(geoTargeting: geo)
        let auction = builder.build()
        XCTAssertEqual(auction.geoTargeting?.location, "US")
    }

    // MARK: - ViewModel edge cases

    func testViewModelWinnerWithNoAsset() async throws {
        let winner = Winner(rank: 1, asset: nil, type: "type", id: "id", resolvedBidId: "bid", campaignId: nil)
        let auctionResult = AuctionResult(resultType: "result_type", winners: [winner], error: false)
        let auctionResponse = AuctionResponse(results: [auctionResult])

        let mockTopsort = MockTopsort(executeAuctionsMockResponse: auctionResponse)
        var config = Configuration(apiKey: "test_api_key")
        config.url = "test_url"
        try Topsort.shared.configure(config)

        let vm = await TopsortBanner.ViewModel()
        let auction = BannerAuctionBuilder(slotId: "s1", deviceType: "mobile").build()
        await vm.executeAuctions(auction: auction, topsort: mockTopsort, onError: nil, onNoWinners: nil)

        await MainActor.run {
            XCTAssertNil(vm.urlString, "No asset means no URL")
            XCTAssertNil(vm.resolvedBidId, "No asset means resolvedBidId stays nil")
        }
    }

    func testViewModelEmptyResults() async throws {
        let auctionResponse = AuctionResponse(results: [])
        let mockTopsort = MockTopsort(executeAuctionsMockResponse: auctionResponse)
        var config = Configuration(apiKey: "test_api_key")
        config.url = "test_url"
        try Topsort.shared.configure(config)

        let vm = await TopsortBanner.ViewModel()
        let auction = BannerAuctionBuilder(slotId: "s1", deviceType: "mobile").build()
        await vm.executeAuctions(auction: auction, topsort: mockTopsort, onError: nil, onNoWinners: nil)

        await MainActor.run {
            XCTAssertFalse(vm.loading)
            XCTAssertNil(vm.resolvedBidId)
        }
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
    func flush() {}
    func executeAuctions(auctions _: [Auction]) async throws(AuctionError) -> AuctionResponse {
        throw .emptyResponse
    }
}
