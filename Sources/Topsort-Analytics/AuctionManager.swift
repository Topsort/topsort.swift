import Foundation

private let AUCTIONS_TOPSORT_URL = URL(string: "https://api.topsort.com/v2/auctions")!
private let MIN_AUCTIONS = 0
private let MAX_AUCTIONS = 5

class AuctionManager {
    public static let shared = AuctionManager()
    private init() {
        self.client = HTTPClient(apiKey: nil)
    }
    private var url: URL = AUCTIONS_TOPSORT_URL
    private var client: HTTPClient

    public func configure(apiKey: String, url: String?) {
        self.client.apiKey = apiKey
        if let url = url {
            guard let url = URL(string: "\(url)/auctions") else {
                fatalError("Invalid URL")
            }
            self.url = url
        }
    }

    public func executeAuctions(auctions: [Auction]) async -> AuctionResponse? {
        if auctions.count > MAX_AUCTIONS || auctions.count == 0 {
            print("Invalid number of auctions: \(auctions.count), must be between \(MIN_AUCTIONS) and \(MAX_AUCTIONS)")
            return nil
        }
        var response: AuctionResponse?
        guard let auctionsData = try? JSONEncoder().encode(["auctions": auctions]) else {
            print("failed to serialize auctions: \(auctions)")
            return nil
        }

        do {
            let resultData = try await self.client.asyncPost(url: self.url, data: auctionsData)
            response = try self.process_response(result: .success(resultData))
        } catch {
            print("Error posting auctions: \(error)")
        }
        return response
    }

    private func process_response(result: Result<Data?, HTTPClientError>) throws -> AuctionResponse? {
        switch result {
            case .success(let data):
                if data == nil {
                    throw HTTPClientError.unknown(error: NSError(domain: "HTTPClient", code: 0, userInfo: nil), data: ErrorData(data: data))
                }
                let resultData = decodeAuctionResponse(data: data!)
                return resultData
            case .failure(let error):
                print("failed to send auctions: \(error)")
                return nil
        }
    }

    private func decodeAuctionResponse(data: Data) -> AuctionResponse? {
        return try? JSONDecoder().decode(AuctionResponse.self, from: data)
    }
}
