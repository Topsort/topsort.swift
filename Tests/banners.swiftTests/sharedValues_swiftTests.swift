import XCTest
@testable import TopsortBanners
@testable import Topsort_Analytics

class SharedValuesTests: XCTestCase {

    func testSharedValuesInitialization() {
        let sharedValues = SharedValues()

        XCTAssertNil(sharedValues.resolvedBidId)
        XCTAssertTrue(sharedValues.loading)
        XCTAssertNil(sharedValues.urlString)
        XCTAssertNil(sharedValues.response)
    }

    func testSetResolvedBidIdAndUrlFromResponse() {
        let asset = Asset(url: "https://example.com")
        let winner = Winner(rank: 1, asset: [asset], type: "type", id: "id", resolvedBidId: "resolved_bid_id")
        let auctionResult = AuctionResult(resultType: "result_type", winners: [winner], error: false)
        let auctionResponse = AuctionResponse(results: [auctionResult])

        let sharedValues = SharedValues()
        sharedValues.response = auctionResponse
        sharedValues.setResolvedBidIdAndUrlFromResponse()

        XCTAssertEqual(sharedValues.resolvedBidId, "resolved_bid_id")
        XCTAssertEqual(sharedValues.urlString, "https://example.com")
    }
}
