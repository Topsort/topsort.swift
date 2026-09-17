import Foundation
@testable import Topsort
import XCTest

class TopsortClientTests: XCTestCase {
    var client: TopsortClient!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        client = try! TopsortClient(apiKey: "test-key", url: "https://proxy.example.com/v2", timeout: 5, configuration: config)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testAuctionsPostsToTheAuctionsEndpointAndDecodes() async throws {
        var seen: URLRequest?
        MockURLProtocol.requestHandler = { request in
            seen = request
            let body = Data("""
            {"results":[{"resultType":"listings","winners":[{"rank":0,"type":"product","id":"p1","resolvedBidId":"bid-1"}],"error":false}]}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let response = try await client.auctions([Auction(type: "listings", slots: 1, device: "mobile", products: AuctionProducts(ids: ["p1"]))])
        XCTAssertEqual(seen?.url?.absoluteString, "https://proxy.example.com/v2/auctions")
        XCTAssertEqual(seen?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(response.results.first?.winners.first?.resolvedBidId, "bid-1")
    }

    func testAuctionsValidatesTheCountBeforeSending() async {
        MockURLProtocol.requestHandler = { _ in XCTFail("must not send"); throw URLError(.badURL) }
        do {
            _ = try await client.auctions([])
            XCTFail("should throw")
        } catch {
            guard case .invalidNumberAuctions(0) = error else { return XCTFail("got \(error)") }
        }
    }

    func testSendPostsOnlyTheNonEmptyEventLists() async throws {
        var body: Data?
        MockURLProtocol.requestHandler = { request in
            let stream = request.httpBodyStream!
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            let read = stream.read(&buffer, maxLength: buffer.count)
            body = Data(buffer[0 ..< max(read, 0)])
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        let click = Event(resolvedBidId: "bid-1", occurredAt: Date.now, opaqueUserId: "u1")
        try await client.send(clicks: [click])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(body)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["clicks"])
        XCTAssertEqual(((json["clicks"] as? [[String: Any]])?.first?["opaqueUserId"]) as? String, "u1")
    }

    /// Regression test: the API rejects a request whose renders array exceeds 50 items with a
    /// 400 — a 51-render call must go out as two requests, not one oversized one.
    func testSendSplits51RendersAcrossTwoRequests() async throws {
        var bodies: [Data] = []
        MockURLProtocol.requestHandler = { request in
            let stream = request.httpBodyStream!
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 16384)
            let read = stream.read(&buffer, maxLength: buffer.count)
            bodies.append(Data(buffer[0 ..< max(read, 0)]))
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        let renders = (0 ..< 51).map { RenderEvent(resolvedBidId: "bid-\($0)", occurredAt: Date.now, opaqueUserId: "u1") }
        try await client.send(renders: renders)

        XCTAssertEqual(bodies.count, 2)
        let sizes = try bodies.map { body -> Int in
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            return try XCTUnwrap(json["renders"] as? [[String: Any]]).count
        }
        XCTAssertEqual(sizes, [50, 1])
    }

    func testSendWithNothingToSendDoesNotPost() async throws {
        MockURLProtocol.requestHandler = { _ in XCTFail("must not send"); throw URLError(.badURL) }
        try await client.send()
    }

    func testSendSurfacesTheStatusCodeAndKeepsNothing() async {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data("{\"message\":\"bad key\",\"errCode\":\"invalid_api_key\"}".utf8))
        }
        do {
            try await client.send(impressions: [Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now, opaqueUserId: "u1")])
            XCTFail("should throw")
        } catch {
            guard case let .statusCode(code, .topsortError(topsortError)?) = error else { return XCTFail("got \(error)") }
            XCTAssertEqual(code, 401)
            guard case .invalidApiKey = topsortError.errCode else { return XCTFail("got \(topsortError.errCode)") }
        }
    }
}
