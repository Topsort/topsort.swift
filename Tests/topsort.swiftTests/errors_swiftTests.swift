import Foundation
@testable import Topsort
import XCTest

class TopsortErrorCodeTests: XCTestCase {
    func testBadRequest() {
        XCTAssertEqual(TopsortErrorCode(rawValue: "bad_request"), .badRequest)
    }

    func testEmptyRequest() {
        XCTAssertEqual(TopsortErrorCode(rawValue: "empty_request"), .emptyRequest)
    }

    func testInternalServerError() {
        XCTAssertEqual(TopsortErrorCode(rawValue: "internal_server_error"), .internalServerError)
    }

    func testInvalidApiKey() {
        XCTAssertEqual(TopsortErrorCode(rawValue: "invalid_api_key"), .invalidApiKey)
    }

    func testResolvedBidIdNotFound() {
        XCTAssertEqual(TopsortErrorCode(rawValue: "resolved_bid_id_not_found"), .resolvedBidIdNotFound)
    }

    func testInvalidEventType() {
        XCTAssertEqual(TopsortErrorCode(rawValue: "invalid_event_type"), .invalidEventType)
    }

    func testUnknownErrorCode() {
        let code = TopsortErrorCode(rawValue: "some_future_error")
        if case let .unknownError(rawCode) = code {
            XCTAssertEqual(rawCode, "some_future_error")
        } else {
            XCTFail("Expected .unknownError")
        }
    }
}

class TopsortErrorDecodingTests: XCTestCase {
    func testDecodeTopsortErrorBadRequest() throws {
        let json = """
        {"message": "Bad request", "errCode": {"badRequest": {}}}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let error = try JSONDecoder().decode(TopsortError.self, from: data)
        XCTAssertEqual(error.message, "Bad request")
        if case .badRequest = error.errCode {} else {
            XCTFail("Expected .badRequest, got \(error.errCode)")
        }
    }

    func testDecodeTopsortErrorInvalidApiKey() throws {
        let json = """
        {"message": "Invalid key", "errCode": {"invalidApiKey": {}}}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let error = try JSONDecoder().decode(TopsortError.self, from: data)
        if case .invalidApiKey = error.errCode {} else {
            XCTFail("Expected .invalidApiKey, got \(error.errCode)")
        }
    }

    func testDecodeTopsortErrorUnknownCode() throws {
        let json = """
        {"message": "New thing", "errCode": {"unknownError": {"code": "new_error_type"}}}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let error = try JSONDecoder().decode(TopsortError.self, from: data)
        if case let .unknownError(code) = error.errCode {
            XCTAssertEqual(code, "new_error_type")
        } else {
            XCTFail("Expected .unknownError, got \(error.errCode)")
        }
    }
}

class ConfigurationErrorTests: XCTestCase {
    func testInvalidURLDescription() {
        let error = ConfigurationError.invalidURL("bad://url")
        XCTAssertEqual(error.errorDescription, "Invalid Topsort API URL: bad://url")
    }

    func testNotConfiguredDescription() {
        let error = ConfigurationError.notConfigured
        XCTAssertTrue(error.errorDescription?.contains("not configured") ?? false)
    }
}

class ValidationErrorTests: XCTestCase {
    func testQualityScoreMismatchDescription() {
        let error = ValidationError.qualityScoreCountMismatch(idsCount: 3, scoresCount: 1)
        XCTAssertTrue(error.errorDescription?.contains("3") ?? false)
        XCTAssertTrue(error.errorDescription?.contains("1") ?? false)
    }
}

/// Make TopsortErrorCode Equatable for test assertions
extension TopsortErrorCode: Equatable {
    public static func == (lhs: TopsortErrorCode, rhs: TopsortErrorCode) -> Bool {
        switch (lhs, rhs) {
        case (.badRequest, .badRequest),
             (.emptyRequest, .emptyRequest),
             (.internalServerError, .internalServerError),
             (.invalidApiKey, .invalidApiKey),
             (.resolvedBidIdNotFound, .resolvedBidIdNotFound),
             (.invalidEventType, .invalidEventType):
            return true
        case let (.unknownError(a), .unknownError(b)):
            return a == b
        default:
            return false
        }
    }
}
