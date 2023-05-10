//
//  File.swift
//  
//
//  Created by Pablo Reszczynski on 10-05-23.
//

import Foundation

enum TopsortError : Error {
    case badRequest(message: String?)
    case emptyRequest(message: String?)
    case internalServerError(message: String?)
    case invalidApiKey(message: String?)
    case resolvedBidIdNotFound(message: String?)
    case invalidEventType(message: String?)
    case unknownError(message: String?)
    
    init(jsonObject: [String: String]) {
        switch(jsonObject["errCode"]) {
        case "bad_request":
            self = .badRequest(message: jsonObject["message"])
        case "empty_request":
            self = .emptyRequest(message: jsonObject["message"])
        case "internal_server_error":
            self = .internalServerError(message: jsonObject["message"])
        case "invalid_api_key":
            self = .invalidApiKey(message: jsonObject["message"])
        case "resolved_bid_id_not_found":
            self = .resolvedBidIdNotFound(message: jsonObject["message"])
        case "invalid_event_type":
            self = .invalidEventType(message: jsonObject["message"])
        default:
            self = .unknownError(message: nil)
        }
    }
}
