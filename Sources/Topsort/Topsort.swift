import Foundation

public protocol TopsortProtocol {
    var opaqueUserId: String { get }
    var isConfigured: Bool { get }
    func set(opaqueUserId: String?)
    func configure(apiKey: String, url: String?, auctionsTimeout: TimeInterval?) throws
    func track(impression event: Event)
    func track(click event: Event)
    func track(purchase event: PurchaseEvent)
    func executeAuctions(auctions: [Auction]) async throws(AuctionError) -> AuctionResponse
}

public class Topsort: TopsortProtocol {
    public static let shared = Topsort()
    public internal(set) var isConfigured = false
    @FilePersistedValue(storePath: PathHelper.path(for: "com.topsort.analytics.opaque-user-id.plist"))
    private var _opaqueUserId: String?
    public var opaqueUserId: String {
        if let oui = _opaqueUserId {
            return oui
        } else {
            let oui = Self.newOpaqueUserId()
            _opaqueUserId = oui
            return oui
        }
    }

    private init() {}
    public func set(opaqueUserId: String?) {
        _opaqueUserId = opaqueUserId ?? Self.newOpaqueUserId()
    }

    public func configure(apiKey: String, url: String? = nil, auctionsTimeout: TimeInterval? = nil) throws(ConfigurationError) {
        try EventManager.shared.configure(apiKey: apiKey, url: url)
        try AuctionManager.shared.configure(apiKey: apiKey, url: url)
        if let timeout = auctionsTimeout {
            AuctionManager.shared.timeoutInterval = timeout
        }
        isConfigured = true
    }

    public func track(impression event: Event) {
        guard isConfigured else {
            print("[Topsort] Warning: track(impression:) called before configure(). Event dropped.")
            return
        }
        EventManager.shared.push(event: .impression(event))
    }

    public func track(click event: Event) {
        guard isConfigured else {
            print("[Topsort] Warning: track(click:) called before configure(). Event dropped.")
            return
        }
        EventManager.shared.push(event: .click(event))
    }

    public func track(purchase event: PurchaseEvent) {
        guard isConfigured else {
            print("[Topsort] Warning: track(purchase:) called before configure(). Event dropped.")
            return
        }
        EventManager.shared.push(event: .purchase(event))
    }

    private static func newOpaqueUserId() -> String {
        UUID().uuidString
    }

    public func executeAuctions(auctions: [Auction]) async throws(AuctionError) -> AuctionResponse {
        guard isConfigured else {
            throw .notConfigured
        }
        return try await AuctionManager.shared.executeAuctions(auctions: auctions)
    }
}
