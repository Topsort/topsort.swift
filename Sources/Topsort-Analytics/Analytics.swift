import Foundation

public class Analytics {
    public static let shared = Analytics()
    @FilePersistedValue(storePath: PathHelper.path(for: "com.topsort.analytics.opaque-user-id.plist"))
    private var _opaqueUserId: String?
    public var opaqueUserId: String {
        get {
            if let oui = _opaqueUserId {
                return oui
            } else {
                let oui = Self.newOpaqueUserId()
                _opaqueUserId = oui
                return oui
            }
        }
    }
    private init() {}
    public func set(opaqueUserId: String?) {
        self._opaqueUserId = opaqueUserId ?? Self.newOpaqueUserId()
    }
    public func configure(apiKey: String, url: String? = nil) {
        EventManager.shared.configure(apiKey: apiKey, url: url)
        AuctionManager.shared.configure(apiKey: apiKey, url: url)
    }
    public func track(impression event: Event) {
        EventManager.shared.push(event: .impression(event))
    }
    public func track(click event: Event) {
        EventManager.shared.push(event: .click(event))
    }
    public func track(purchase event: PurchaseEvent) {
        EventManager.shared.push(event: .purchase(event))
    }
    private static func newOpaqueUserId() -> String { UUID().uuidString }

    public func executeAuctions(auctions: [Auction]) async -> AuctionResponse? {
        return await AuctionManager.shared.executeAuctions(auctions: auctions)
    }
}
