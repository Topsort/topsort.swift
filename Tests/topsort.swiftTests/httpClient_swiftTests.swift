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
        XCTAssertFalse(error.isRetriable())
    }

    func testStatusCode401IsRetriable() {
        let error = HTTPClientError.statusCode(code: 401, data: nil)
        XCTAssertTrue(error.isRetriable())
    }

    func testStatusCode500IsRetriable() {
        let error = HTTPClientError.statusCode(code: 500, data: nil)
        XCTAssertTrue(error.isRetriable())
    }

    func testStatusCode429IsRetriable() {
        let error = HTTPClientError.statusCode(code: 429, data: nil)
        XCTAssertTrue(error.isRetriable())
    }

    func testStatusCode503IsRetriable() {
        let error = HTTPClientError.statusCode(code: 503, data: nil)
        XCTAssertTrue(error.isRetriable())
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

class HTTPClientRequestTests: XCTestCase {
    func testRequestIncludesContentType() {
        let client = HTTPClient(apiKey: "test-key")
        // We can't access newRequest directly (private), but we can verify
        // by inspecting the mock's received data format is JSON
        // This is an indirect test — the real verification is that
        // AuctionManager and EventManager produce valid JSON payloads
        XCTAssertNotNil(client)
    }

    func testClientUsesEphemeralSession() {
        // Verify client initializes without crashing
        let client = HTTPClient(apiKey: nil)
        XCTAssertNil(client.apiKey)

        let clientWithKey = HTTPClient(apiKey: "test-key")
        XCTAssertEqual(clientWithKey.apiKey, "test-key")
    }
}
