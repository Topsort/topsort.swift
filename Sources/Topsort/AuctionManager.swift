import Foundation

private let AUCTIONS_TOPSORT_URL = URL(string: "https://api.topsort.com/v2/auctions")!
private let MIN_AUCTIONS = 1
private let MAX_AUCTIONS = 5

public enum AuctionError: Error {
    case http(error: HTTPClientError)
    case invalidNumberAuctions(count: Int)
    case serializationError
    case deserializationError(error: Error, data: Data)
    case emptyResponse
}

class AuctionManager {
    public static let shared = AuctionManager()
    private init() {
        client = HTTPClient(apiKey: nil)
    }

    var url: URL = AUCTIONS_TOPSORT_URL
    var client: HTTPClient
    public var timeoutInterval: TimeInterval = 60

    public func configure(apiKey: String, url: String?) {
        client.apiKey = apiKey
        if let url = url {
            guard let url = URL(string: "\(url)/auctions") else {
                fatalError("Invalid URL")
            }
            self.url = url
        }
    }

    public func executeAuctions(auctions: [Auction]) async throws(AuctionError) -> AuctionResponse {
        if auctions.count > MAX_AUCTIONS || auctions.count < MIN_AUCTIONS {
            print("Invalid number of auctions: \(auctions.count), must be between \(MIN_AUCTIONS) and \(MAX_AUCTIONS)")
            throw AuctionError.invalidNumberAuctions(count: auctions.count)
        }
        guard let auctionsData = try? JSONEncoder().encode(["auctions": auctions]) else {
            print("failed to serialize auctions: \(auctions)")
            throw AuctionError.serializationError
        }
        
        let result: Result<Data?, HTTPClientError>;
        do {
            let data = try await client.asyncPost(url: url, data: auctionsData, timeoutInterval: timeoutInterval)
            result = .success(data)
        } catch {
            result = .failure(error)
        }
        
        return try process_response(result: result)
    }

    private func process_response(result: Result<Data?, HTTPClientError>) throws(AuctionError) -> AuctionResponse {
        switch result {
        case let .success(data):
            guard let data = data else {
                throw .emptyResponse
            }
            return try decodeAuctionResponse(data: data)
        case let .failure(error):
            print("failed to send auctions: \(error)")
            throw .http(error: error)
        }
    }

    private func decodeAuctionResponse(data: Data) throws(AuctionError) -> AuctionResponse {
        do {
            return try JSONDecoder().decode(AuctionResponse.self, from: data)
        } catch {
            throw .deserializationError(error: error, data: data)
        }
    }
}
