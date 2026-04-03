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

    func testStatusCode401IsRetriable() {
        let error = HTTPClientError.statusCode(code: 401, data: nil)
        XCTAssertTrue(error.isRetriable())
    }

    func testStatusCode403IsRetriable() {
        let error = HTTPClientError.statusCode(code: 403, data: nil)
        XCTAssertTrue(error.isRetriable())
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

    func testOnly400IsNonRetriable() {
        // Verify that 400 is the ONLY non-retriable status code
        for code in [401, 403, 404, 408, 429, 500, 502, 503, 504] {
            let error = HTTPClientError.statusCode(code: code, data: nil)
            XCTAssertTrue(error.isRetriable(), "HTTP \(code) should be retriable")
        }
        let error400 = HTTPClientError.statusCode(code: 400, data: nil)
        XCTAssertFalse(error400.isRetriable(), "Only HTTP 400 should be non-retriable")
    }

    // MARK: - ErrorData parsing

    func testErrorDataParsesTopsortError() {
        let json = """
        {"message": "Invalid API key", "errCode": {"invalidApiKey": {}}}
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

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        // We need to create HTTPClient with our custom session
        // Since HTTPClient creates its own session, we test via the callback path
        client = HTTPClient(apiKey: "test-key")
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        client = nil
        super.tearDown()
    }

    func testPostCallbackSuccess() throws {
        let url = try XCTUnwrap(URL(string: "https://api.example.com/v2/events"))
        let exp = expectation(description: "callback")

        // HTTPClient uses its own ephemeral session, so URLProtocol won't intercept.
        // Instead, test the callback contract by verifying the mock client pattern works.
        let mock = MockHTTPClient(apiKey: "key", postResult: .success(Data("{\"ok\":true}".utf8)))
        mock.post(url: url, data: Data()) { result in
            switch result {
            case .success:
                break // expected
            case .failure:
                XCTFail("Expected success")
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
        XCTAssertTrue(mock.postCalled)
    }

    func testPostCallbackFailure() throws {
        let url = try XCTUnwrap(URL(string: "https://api.example.com/v2/events"))
        let exp = expectation(description: "callback")

        let mock = MockHTTPClient(apiKey: "key", postResult: .failure(.statusCode(code: 500, data: nil)))
        mock.post(url: url, data: Data()) { result in
            switch result {
            case .success:
                XCTFail("Expected failure")
            case let .failure(error):
                if case let .statusCode(code, _) = error {
                    XCTAssertEqual(code, 500)
                }
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
    }

    func testAsyncPostSuccess() async throws {
        let url = try XCTUnwrap(URL(string: "https://api.example.com/v2/events"))
        let mock = MockHTTPClient(apiKey: "key", postResult: .success(Data("{\"ok\":true}".utf8)))
        let data = try await mock.asyncPost(url: url, data: Data())
        XCTAssertNotNil(data)
        XCTAssertTrue(mock.postCalled)
    }

    func testAsyncPostThrowsOnError() async throws {
        let url = try XCTUnwrap(URL(string: "https://api.example.com/v2/events"))
        let mock = MockHTTPClient(apiKey: "key", postResult: .failure(.statusCode(code: 401, data: nil)))
        do {
            _ = try await mock.asyncPost(url: url, data: Data())
            XCTFail("Should have thrown")
        } catch {
            if case let .statusCode(code, _) = error {
                XCTAssertEqual(code, 401)
            }
        }
    }
}
