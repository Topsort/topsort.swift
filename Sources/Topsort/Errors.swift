import Foundation

public enum ConfigurationError: LocalizedError {
    case invalidURL(String)
    case invalidFlushAt(Int)
    case invalidFlushInterval(TimeInterval)
    case notConfigured

    public var errorDescription: String? {
        switch self {
        case let .invalidURL(url):
            return "Invalid Topsort API URL: \(url)"
        case let .invalidFlushAt(value):
            return "flushAt must be at least 1, got \(value)"
        case let .invalidFlushInterval(value):
            return "flushInterval must be greater than 0, got \(value)"
        case .notConfigured:
            return "Topsort SDK is not configured. Call Topsort.shared.configure(apiKey:) before use."
        }
    }
}

public enum ValidationError: LocalizedError {
    case qualityScoreCountMismatch(idsCount: Int, scoresCount: Int)

    public var errorDescription: String? {
        switch self {
        case let .qualityScoreCountMismatch(idsCount, scoresCount):
            return "Quality scores count (\(scoresCount)) must match product IDs count (\(idsCount))"
        }
    }
}

public struct TopsortError: Error, Decodable {
    /// Only `errCode` is required by the API.
    public let message: String?
    public let errCode: TopsortErrorCode
}

public enum TopsortErrorCode: Decodable {
    /// The API sends the code as a string (`"invalid_api_key"`); the synthesized decoder would
    /// expect an object keyed by case name and never match a real response.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TopsortErrorCode(rawValue: raw) ?? .unknownError(code: raw)
    }

    case badRequest
    case emptyRequest
    case internalServerError
    case invalidApiKey
    case resolvedBidIdNotFound
    case invalidEventType
    case unknownError(code: String)

    public init?(rawValue: String) {
        switch rawValue {
        case "bad_request":
            self = .badRequest
        case "empty_request":
            self = .emptyRequest
        case "internal_server_error":
            self = .internalServerError
        case "invalid_api_key":
            self = .invalidApiKey
        case "resolved_bid_id_not_found":
            self = .resolvedBidIdNotFound
        case "invalid_event_type":
            self = .invalidEventType
        default:
            self = .unknownError(code: rawValue)
        }
    }
}
