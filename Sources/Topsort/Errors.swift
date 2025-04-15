import Foundation

public struct TopsortError: Error, Decodable {
    let message: String
    let errCode: TopsortErrorCode
}

public enum TopsortErrorCode: Decodable {
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
