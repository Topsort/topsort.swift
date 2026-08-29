import Foundation

public protocol TopsortProtocol {
    var opaqueUserId: String { get }
    var isConfigured: Bool { get }
    func set(opaqueUserId: String?)
    func configure(_ configuration: Configuration) throws
    func track(impression event: Event)
    func track(click event: Event)
    func track(purchase event: PurchaseEvent)
    func track(pageview event: PageViewEvent)
    func flush()
    func executeAuctions(auctions: [Auction]) async throws(AuctionError) -> AuctionResponse
}

/// Default implementation for backward compatibility with existing conformers.
public extension TopsortProtocol {
    func track(pageview _: PageViewEvent) {}
}

public class Topsort: TopsortProtocol {
    public static let shared = Topsort()
    public internal(set) var isConfigured = false
    @FilePersistedValue(storePath: PathHelper.path(for: "com.topsort.analytics.opaque-user-id.plist"))
    private var _opaqueUserId: String?
    // Read from Event initializers on any thread, written by configure and set(opaqueUserId:).
    private let identityLock = NSLock()
    private var identity: Identity = .persisted
    private var ephemeralOpaqueUserId: String?
    public var opaqueUserId: String {
        identityLock.withLock {
            switch identity {
            case .ephemeral:
                if let id = ephemeralOpaqueUserId { return id }
                let id = Self.newOpaqueUserId()
                ephemeralOpaqueUserId = id
                return id
            case .persisted:
                if let oui = _opaqueUserId {
                    return oui
                } else {
                    let oui = Self.newOpaqueUserId()
                    _opaqueUserId = oui
                    return oui
                }
            }
        }
    }

    private init() {}
    /// Under `.ephemeral` the id is held in memory only; `nil` mints a new one either way.
    public func set(opaqueUserId: String?) {
        identityLock.withLock {
            switch identity {
            case .ephemeral: ephemeralOpaqueUserId = opaqueUserId ?? Self.newOpaqueUserId()
            case .persisted: _opaqueUserId = opaqueUserId ?? Self.newOpaqueUserId()
            }
        }
    }

    public func configure(_ configuration: Configuration) throws(ConfigurationError) {
        try EventManager.shared.configure(
            apiKey: configuration.apiKey,
            url: configuration.url,
            flushAt: configuration.flushAt,
            flushInterval: configuration.flushInterval,
            onEventsDiscarded: configuration.onEventsDiscarded
        )
        Logger.logLevel = configuration.logLevel
        identityLock.withLock {
            // Entering ephemeral forgets the stored id (the file is removed asynchronously) and
            // any id set before this call. A reconfigure that is already ephemeral keeps the
            // process's id, so an impression and its click stay linked across a token refresh.
            if configuration.identity == .ephemeral, identity != .ephemeral {
                _opaqueUserId = nil
                ephemeralOpaqueUserId = nil
            }
            identity = configuration.identity
        }
        try AuctionManager.shared.configure(apiKey: configuration.apiKey, url: configuration.url)
        if let timeout = configuration.auctionsTimeout {
            AuctionManager.shared.timeoutInterval = timeout
        }
        isConfigured = true
    }

    @available(*, deprecated, message: "Use configure(_:) with a Configuration struct")
    public func configure(apiKey: String, url: String? = nil, auctionsTimeout: TimeInterval? = nil) throws {
        var config = Configuration(apiKey: apiKey)
        config.url = url
        config.auctionsTimeout = auctionsTimeout
        try configure(config)
    }

    public func track(impression event: Event) {
        guard isConfigured else {
            Logger.warning("track(impression:) called before configure(). Event dropped.")
            return
        }
        EventManager.shared.push(event: .impression(event))
    }

    public func track(click event: Event) {
        guard isConfigured else {
            Logger.warning("track(click:) called before configure(). Event dropped.")
            return
        }
        EventManager.shared.push(event: .click(event))
    }

    public func track(purchase event: PurchaseEvent) {
        guard isConfigured else {
            Logger.warning("track(purchase:) called before configure(). Event dropped.")
            return
        }
        EventManager.shared.push(event: .purchase(event))
    }

    public func track(pageview event: PageViewEvent) {
        guard isConfigured else {
            Logger.warning("track(pageview:) called before configure(). Event dropped.")
            return
        }
        EventManager.shared.push(event: .pageview(event))
    }

    public func flush() {
        EventManager.shared.flush()
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
