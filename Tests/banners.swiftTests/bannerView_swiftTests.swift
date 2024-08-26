@testable import Topsort
@testable import TopsortBanners
import XCTest

class TopsortBannerTests: XCTestCase {
    func testTopsortBannerInitialization() {
        let expectation = self.expectation(description: "Button clicked action")
        let banner = TopsortBanner(
            apiKey: "test_api_key",
            url: "test_url",
            width: 300,
            height: 250,
            slotId: "test_slot_id",
            deviceType: "test_device_type"
        ) { _ in
            expectation.fulfill()
        }

        XCTAssertEqual(banner.width, 300)
        XCTAssertEqual(banner.height, 250)

        banner.buttonClickedAction(nil)

        wait(for: [expectation], timeout: 1.0)
    }

    func testExecuteAuctions() async {
        // Mock the response
        let asset = Asset(url: "https://example.com")
        let winner = Winner(rank: 1, asset: [asset], type: "type", id: "id", resolvedBidId: "resolved_bid_id")
        let auctionResult = AuctionResult(resultType: "result_type", winners: [winner], error: false)
        let auctionResponse = AuctionResponse(results: [auctionResult])

        // Mock Topsort and response
        let mockTopsort = MockTopsort()
        mockTopsort.executeAuctionsMockResponse = auctionResponse

        let banner = await TopsortBanner(
            apiKey: "test_api_key",
            url: "test_url",
            width: 300,
            height: 250,
            slotId: "test_slot_id",
            deviceType: "test_device_type",
            buttonClickedAction: { _ in
            },
            topsort: mockTopsort
        )

        // Execute the method
        await banner.executeAuctions(deviceType: "test_device_type", slotId: "test_slot_id")

        await MainActor.run {
            XCTAssertEqual(banner.sharedValues.resolvedBidId, "resolved_bid_id")
            XCTAssertEqual(banner.sharedValues.urlString, "https://example.com")
            XCTAssertFalse(banner.sharedValues.loading)
        }
    }
}
