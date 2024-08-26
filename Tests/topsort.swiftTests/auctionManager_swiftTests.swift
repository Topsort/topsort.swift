import Foundation
@testable import Topsort
import XCTest

class AuctionManagerTests: XCTestCase {
    var auctionManager: AuctionManager!
    var mockClient: MockHTTPClient!

    override func setUp() {
        super.setUp()
        mockClient = MockHTTPClient(apiKey: nil, postResult: .success(Data()))
        auctionManager = AuctionManager.shared
        auctionManager.client = mockClient
    }

    override func tearDown() {
        auctionManager = nil
        mockClient = nil
        super.tearDown()
    }

    func testConfigure() {
        let apiKey = "testApiKey"
        let urlString = "https://test.com"
        auctionManager.configure(apiKey: apiKey, url: urlString)

        XCTAssertEqual(mockClient.apiKey, apiKey)
        XCTAssertEqual(auctionManager.url.absoluteString, "\(urlString)/auctions")
    }

    func testExecuteAuctionsWithValidAuctions() async {
        let auctions = [Auction(type: "mobile", slots: 1), Auction(type: "mobile", slots: 1)]
        let responseData = Data(
            """
            {
                "results": [
                    {
                        "resultType": "banner",
                        "winners": [
                            {
                                "rank": 1,
                                "asset": [
                                    {
                                        "url": "https://test.com"
                                    }
                                ],
                                "type": "test",
                                "id": "test",
                                "resolvedBidId": "test"
                            }
                        ],
                        "error": false
                    }
                ]
            }
            """.utf8
        )
        mockClient.postResult = .success(responseData)

        let response = await auctionManager.executeAuctions(auctions: auctions)

        XCTAssertTrue(mockClient.postCalled)
        XCTAssertNotNil(response)
    }

    func testExecuteAuctionsWithTooManyAuctions() async {
        let auctions = Array(repeating: Auction(type: "mobile", slots: 1), count: 6)

        let response = await auctionManager.executeAuctions(auctions: auctions)

        XCTAssertFalse(mockClient.postCalled)
        XCTAssertNil(response)
    }

    func testExecuteAuctionsWithSerializationError() async {
        let auctions = [Auction(type: "mobile", slots: 1)]
        let responseData = Data(
            """
            {
                "notValidKey": [
                    {
                        "anotherNotValidKey": "banner",
                    }
                ]
            }
            """.utf8
        )
        mockClient.postResult = .success(responseData)

        let response = await auctionManager.executeAuctions(auctions: auctions)

        XCTAssertTrue(mockClient.postCalled)
        XCTAssertNil(response)
    }

    func testExecuteAuctionsWithPostError() async {
        let auctions = [Auction(type: "mobile", slots: 1)]
        mockClient.postResult = .failure(.unknown(error: NSError(domain: "Test", code: 1, userInfo: nil), data: nil))

        let response = await auctionManager.executeAuctions(auctions: auctions)

        XCTAssertTrue(mockClient.postCalled)
        XCTAssertNil(response)
    }
}
