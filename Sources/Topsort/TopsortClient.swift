import Foundation

/// Nothing kept: no queue, no retry, no persistence, no identity — `send` issues only as many
/// sequential requests as the API's per-type array limit requires. For hosts that run their own
/// event pipeline and want the models and the transport without the SDK's delivery guarantees.
/// `Topsort.shared` remains the recommended path.
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

    /// Reports events, splitting into as many sequential requests as needed to keep each
    /// renders/impressions/clicks/purchases/pageviews array at or under the API's per-type
    /// limit (`MAX_EVENTS_PER_TYPE_PER_BATCH`) — past it the API rejects the whole request with
    /// a 400. Nothing is retried: a thrown error means the caller still owns every event from
    /// that request onward. Retrying is only safe if the caller resends the exact same event
    /// values it passed originally — the API dedupes on each event's `id`, but that `id` is a
    /// fresh `UUID()` by default, so reconstructing the events from source data on retry (rather
    /// than reusing the array from the failed call) mints new ids and defeats the dedupe, risking
    /// double-billed or double-attributed events for whatever chunk actually made it through.
    /// Pass `opaqueUserId` to every event — the initializers' default reaches for
    /// `Topsort.shared`, which mints and persists a device id, so omitting it is not stateless.
    public func send(impressions: [Event] = [], clicks: [Event] = [], purchases: [PurchaseEvent] = [], pageviews: [PageViewEvent] = [], renders: [RenderEvent] = []) async throws(HTTPClientError) {
        guard !(impressions.isEmpty && clicks.isEmpty && purchases.isEmpty && pageviews.isEmpty && renders.isEmpty) else { return }

        let impressionChunks = impressions.chunked(into: MAX_EVENTS_PER_TYPE_PER_BATCH)
        let clickChunks = clicks.chunked(into: MAX_EVENTS_PER_TYPE_PER_BATCH)
        let purchaseChunks = purchases.chunked(into: MAX_EVENTS_PER_TYPE_PER_BATCH)
        let pageviewChunks = pageviews.chunked(into: MAX_EVENTS_PER_TYPE_PER_BATCH)
        let renderChunks = renders.chunked(into: MAX_EVENTS_PER_TYPE_PER_BATCH)
        let requestCount = [impressionChunks.count, clickChunks.count, purchaseChunks.count, pageviewChunks.count, renderChunks.count].max() ?? 0

        for index in 0 ..< requestCount {
            let events = Events(
                impressions: index < impressionChunks.count ? impressionChunks[index] : nil,
                clicks: index < clickChunks.count ? clickChunks[index] : nil,
                purchases: index < purchaseChunks.count ? purchaseChunks[index] : nil,
                pageviews: index < pageviewChunks.count ? pageviewChunks[index] : nil,
                renders: index < renderChunks.count ? renderChunks[index] : nil
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
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard !isEmpty else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
