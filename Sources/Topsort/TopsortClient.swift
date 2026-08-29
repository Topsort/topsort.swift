import Foundation

/// One request at a time, nothing kept: no queue, no retry, no persistence, no identity. For
/// hosts that run their own event pipeline and want the models and the transport without the
/// SDK's delivery guarantees. `Topsort.shared` remains the recommended path.
public struct TopsortClient {
    private let client: HTTPClient
    private let auctionsURL: URL
    private let eventsURL: URL
    private let timeout: TimeInterval

    /// - Parameters:
    ///   - url: API base including the version path, e.g. `https://proxy.example.com/v2`.
    ///   - timeout: per-request, in seconds.
    public init(apiKey: String, url: String = "https://api.topsort.com/v2", timeout: TimeInterval = 60) throws(ConfigurationError) {
        try self.init(apiKey: apiKey, url: url, timeout: timeout, configuration: .ephemeral)
    }

    init(apiKey: String, url: String, timeout: TimeInterval, configuration: URLSessionConfiguration) throws(ConfigurationError) {
        guard let auctionsURL = URL(string: "\(url)/auctions"), let eventsURL = URL(string: "\(url)/events") else {
            throw .invalidURL(url)
        }
        client = HTTPClient(apiKey: apiKey, configuration: configuration)
        self.auctionsURL = auctionsURL
        self.eventsURL = eventsURL
        self.timeout = timeout
    }

    /// Runs 1–5 auctions and returns the winners.
    public func auctions(_ auctions: [Auction]) async throws(AuctionError) -> AuctionResponse {
        try await AuctionManager.executeAuctions(auctions, client: client, url: auctionsURL, timeout: timeout)
    }

    /// Reports events in one request. Nothing is retried: a thrown error means the caller still
    /// owns the events. Pass `opaqueUserId` to every event — the initializers' default reaches
    /// for `Topsort.shared`, which mints and persists a device id, so omitting it is not stateless.
    public func send(impressions: [Event] = [], clicks: [Event] = [], purchases: [PurchaseEvent] = [], pageviews: [PageViewEvent] = []) async throws(HTTPClientError) {
        guard !(impressions.isEmpty && clicks.isEmpty && purchases.isEmpty && pageviews.isEmpty) else { return }
        let events = Events(
            impressions: impressions.isEmpty ? nil : impressions,
            clicks: clicks.isEmpty ? nil : clicks,
            purchases: purchases.isEmpty ? nil : purchases,
            pageviews: pageviews.isEmpty ? nil : pageviews
        )
        let body: Data
        do {
            body = try JSONEncoder().encode(events)
        } catch {
            throw .unknown(error: error, data: nil)
        }
        _ = try await client.asyncPost(url: eventsURL, data: body, timeoutInterval: timeout)
    }
}
