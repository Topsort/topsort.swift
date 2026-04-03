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
