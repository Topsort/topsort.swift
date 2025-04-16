@testable import Topsort
@testable import TopsortBanners
import XCTest

class TopsortBannerTests: XCTestCase {
    func testTopsortBannerInitialization() {
        Topsort.shared.configure(apiKey: "test_api_key", url: "test_url")
        let expectation = self.expectation(description: "Button clicked action")
        let banner = TopsortBanner(bannerAuctionBuilder: .init(
            slotId: "test_slot_id",
            deviceType: "test_device_type"
        )
        ).buttonClickedAction { _ in
            expectation.fulfill()
        }

        banner.buttonClickedAction?(nil)

        wait(for: [expectation], timeout: 1.0)
    }

    func testExecuteAuctions() async {
        // Mock the response
        let asset = Asset(url: "https://example.com")
        let winner = Winner(rank: 1, asset: [asset], type: "type", id: "id", resolvedBidId: "resolved_bid_id")
        let auctionResult = AuctionResult(resultType: "result_type", winners: [winner], error: false)
        let auctionResponse = AuctionResponse(results: [auctionResult])

        // Mock Topsort and response
        let mockTopsort = MockTopsort(executeAuctionsMockResponse: auctionResponse)
        Topsort.shared.configure(apiKey: "test_api_key", url: "test_url")

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
}
