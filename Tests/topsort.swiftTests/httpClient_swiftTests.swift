import Foundation
@testable import Topsort
import XCTest

class HTTPClientErrorTests: XCTestCase {
    // MARK: - isRetriable

    func testUnknownErrorIsRetriable() {
        let error = HTTPClientError.unknown(error: NSError(domain: "test", code: 0), data: nil)
        XCTAssertTrue(error.isRetriable())
    }

    func testStatusCode400IsNotRetriable() {
        let error = HTTPClientError.statusCode(code: 400, data: nil)
        XCTAssertFalse(error.isRetriable(), "400 Bad Request should NOT be retriable")
    }

    func testStatusCode401IsNotRetriable() {
        let error = HTTPClientError.statusCode(code: 401, data: nil)
        XCTAssertFalse(error.isRetriable(), "401 Unauthorized is permanent — a bad API key never becomes good by retrying")
    }

    func testStatusCode403IsNotRetriable() {
        let error = HTTPClientError.statusCode(code: 403, data: nil)
        XCTAssertFalse(error.isRetriable(), "403 Forbidden should NOT be retriable")
    }

    func testStatusCode408IsRetriable() {
        let error = HTTPClientError.statusCode(code: 408, data: nil)
        XCTAssertTrue(error.isRetriable(), "408 Request Timeout invites a later attempt")
    }

    func testStatusCode429IsRetriable() {
        let error = HTTPClientError.statusCode(code: 429, data: nil)
        XCTAssertTrue(error.isRetriable())
    }

    func testStatusCode500IsRetriable() {
        let error = HTTPClientError.statusCode(code: 500, data: nil)
        XCTAssertTrue(error.isRetriable())
    }

    func testStatusCode502IsRetriable() {
        let error = HTTPClientError.statusCode(code: 502, data: nil)
        XCTAssertTrue(error.isRetriable())
    }

    func testStatusCode503IsRetriable() {
        let error = HTTPClientError.statusCode(code: 503, data: nil)
        XCTAssertTrue(error.isRetriable())
    }

    func testClientErrorsAreNotRetriableExceptTimeoutAndRateLimit() {
        // 4xx is permanent: the same payload will fail the same way every time. Retrying
        // spends the 50-retry budget and keeps the batch on disk for nothing.
        for code in [400, 401, 403, 404, 405, 409, 413, 415, 422] {
            let error = HTTPClientError.statusCode(code: code, data: nil)
            XCTAssertFalse(error.isRetriable(), "HTTP \(code) should NOT be retriable")
        }
        for code in [408, 429] {
            let error = HTTPClientError.statusCode(code: code, data: nil)
            XCTAssertTrue(error.isRetriable(), "HTTP \(code) should be retriable")
        }
    }

    func testServerErrorsAreRetriable() {
        for code in [500, 501, 502, 503, 504] {
            let error = HTTPClientError.statusCode(code: code, data: nil)
            XCTAssertTrue(error.isRetriable(), "HTTP \(code) should be retriable")
        }
    }

    // MARK: - ErrorData parsing

    func testErrorDataParsesTopsortError() {
        let json = """
        {"message": "Invalid API key", "errCode": "invalid_api_key"}
        """
        let data = json.data(using: .utf8)
        let errorData = ErrorData(data: data)

        if case let .topsortError(tsError) = errorData {
            XCTAssertEqual(tsError.message, "Invalid API key")
            if case .invalidApiKey = tsError.errCode {} else {
                XCTFail("Expected .invalidApiKey")
            }
        } else {
            XCTFail("Expected .topsortError")
        }
    }

    func testErrorDataFallsBackToRawData() {
        let data = "not json".data(using: .utf8)
        let errorData = ErrorData(data: data)

        if case let .data(rawData) = errorData {
            XCTAssertEqual(rawData, data)
        } else {
            XCTFail("Expected .data fallback")
        }
    }

    func testErrorDataReturnsNilForNilInput() {
        let errorData = ErrorData(data: nil)
        XCTAssertNil(errorData)
    }
}

class HTTPClientInitTests: XCTestCase {
    func testClientInitWithNilApiKey() {
        let client = HTTPClient(apiKey: nil)
        XCTAssertNil(client.apiKey)
    }

    func testClientInitWithApiKey() {
        let client = HTTPClient(apiKey: "test-key")
        XCTAssertEqual(client.apiKey, "test-key")
    }

    func testClientApiKeyMutable() {
        let client = HTTPClient(apiKey: nil)
        client.apiKey = "new-key"
        XCTAssertEqual(client.apiKey, "new-key")
    }
}

// MARK: - Request construction

class HTTPClientRequestTests: XCTestCase {
    let testURL = URL(string: "https://api.example.com/v2/events")!

    func testNewRequestSetsContentType() {
        let client = HTTPClient(apiKey: nil)
        let request = client.newRequest(url: testURL, method: "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8")
    }

    func testNewRequestSetsUserAgent() throws {
        let client = HTTPClient(apiKey: nil)
        let request = client.newRequest(url: testURL, method: "POST")
        let userAgent = request.value(forHTTPHeaderField: "User-Agent")
        XCTAssertNotNil(userAgent)
        XCTAssertTrue(try XCTUnwrap(userAgent?.hasPrefix("analytics-swift/")))
    }

    func testNewRequestSetsBearerAuth() {
        let client = HTTPClient(apiKey: "sk_test_123")
        let request = client.newRequest(url: testURL, method: "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk_test_123")
    }

    func testNewRequestOmitsAuthWhenNilApiKey() {
        let client = HTTPClient(apiKey: nil)
        let request = client.newRequest(url: testURL, method: "POST")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testNewRequestSetsHttpMethod() {
        let client = HTTPClient(apiKey: nil)
        let request = client.newRequest(url: testURL, method: "POST")
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testNewRequestSetsCachePolicy() {
        let client = HTTPClient(apiKey: nil)
        let request = client.newRequest(url: testURL, method: "POST")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testNewRequestSetsURL() {
        let client = HTTPClient(apiKey: nil)
        let request = client.newRequest(url: testURL, method: "POST")
        XCTAssertEqual(request.url, testURL)
    }

    func testNewRequestDefaultTimeout() {
        let client = HTTPClient(apiKey: nil)
        let request = client.newRequest(url: testURL, method: "POST")
        XCTAssertEqual(request.timeoutInterval, 60)
    }
}

// MARK: - URLProtocol-based integration tests

class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data?))?

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

class HTTPClientIntegrationTests: XCTestCase {
    var client: HTTPClient!
    let url = URL(string: "https://api.example.com/v2/events")!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        client = HTTPClient(apiKey: "test-key", configuration: config)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        client = nil
        super.tearDown()
    }

    private func respond(_ status: Int, body: String? = nil, capture: ((URLRequest) -> Void)? = nil) {
        MockURLProtocol.requestHandler = { request in
            capture?(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, body.map { Data($0.utf8) })
        }
    }

    private func post(_ data: Data = Data("{}".utf8)) -> Result<Data?, HTTPClientError> {
        let exp = expectation(description: "callback")
        var result: Result<Data?, HTTPClientError>!
        client.post(url: url, data: data) { result = $0; exp.fulfill() }
        wait(for: [exp], timeout: 5)
        return result
    }

    // MARK: post (the events pipeline's path)

    func testPostSendsTheBodyWithAuthAndUserAgentHeaders() throws {
        var seen: URLRequest?
        respond(200, body: "{}", capture: { seen = $0 })
        _ = post(Data("{\"impressions\":[]}".utf8))
        let request = try XCTUnwrap(seen)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "analytics-swift/\(__analytics_version)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8")
        // URLProtocol exposes the body as a stream; read it back.
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        var buffer = [UInt8](repeating: 0, count: 64)
        let read = stream.read(&buffer, maxLength: buffer.count)
        XCTAssertEqual(String(decoding: buffer[0 ..< max(read, 0)], as: UTF8.self), "{\"impressions\":[]}")
    }

    func testPost2xxIsSuccessWithTheBody() {
        respond(200, body: "{\"ok\":true}")
        guard case let .success(data) = post() else { return XCTFail("expected success") }
        XCTAssertEqual(data, Data("{\"ok\":true}".utf8))
    }

    func testPost4xxMapsToStatusCodeWithParsedTopsortError() {
        respond(401, body: "{\"message\":\"bad key\",\"errCode\":\"invalid_api_key\"}")
        guard case let .failure(.statusCode(code, data)) = post() else { return XCTFail("expected statusCode") }
        XCTAssertEqual(code, 401)
        guard case let .topsortError(error) = data else { return XCTFail("expected a parsed TopsortError, got \(String(describing: data))") }
        XCTAssertEqual(error.message, "bad key")
        guard case .invalidApiKey = error.errCode else { return XCTFail("expected invalidApiKey, got \(error.errCode)") }
    }

    func testPost5xxMapsToStatusCode() {
        respond(503)
        guard case let .failure(.statusCode(code, data)) = post() else { return XCTFail("expected statusCode") }
        XCTAssertEqual(code, 503)
        guard case let .data(body) = data else { return XCTFail("expected raw data, got \(String(describing: data))") }
        XCTAssertTrue(body.isEmpty) // URLSession hands back empty Data, not nil
    }

    func testPostTransportFailureMapsToUnknown() {
        MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
        guard case let .failure(.unknown(error, _)) = post() else { return XCTFail("expected unknown") }
        XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
    }

    // MARK: asyncPost (the auctions path)

    func testAsyncPostReturnsTheBodyOn2xx() async throws {
        respond(200, body: "{\"results\":[]}")
        let data = try await client.asyncPost(url: url, data: Data("{}".utf8))
        XCTAssertEqual(data, Data("{\"results\":[]}".utf8))
    }

    func testAsyncPostThrowsStatusCodeOn4xx() async {
        respond(400, body: "{\"message\":\"nope\",\"errCode\":\"bad_request\"}")
        do {
            _ = try await client.asyncPost(url: url, data: Data("{}".utf8))
            XCTFail("should have thrown")
        } catch {
            guard case let .statusCode(code, _) = error else { return XCTFail("expected statusCode, got \(error)") }
            XCTAssertEqual(code, 400)
        }
    }

    func testAsyncPostThrowsUnknownOnTransportFailure() async {
        MockURLProtocol.requestHandler = { _ in throw URLError(.timedOut) }
        do {
            _ = try await client.asyncPost(url: url, data: Data("{}".utf8))
            XCTFail("should have thrown")
        } catch {
            guard case .unknown = error else { return XCTFail("expected unknown, got \(error)") }
        }
    }
}
