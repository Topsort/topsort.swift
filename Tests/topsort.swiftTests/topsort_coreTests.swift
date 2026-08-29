@testable import Topsort
import XCTest

class TopsortCoreTests: XCTestCase {
    var mockClient: MockHTTPClient!

    override func setUp() {
        super.setUp()
        mockClient = MockHTTPClient(apiKey: "test-key", postResult: .success(Data()))
        EventManager.shared.client = mockClient
        EventManager.shared._eventQueue = []
        EventManager.shared._pendingEvents = [:]
        EventManager.shared.flushAt = 1
        #if canImport(Network)
            let mockNetwork = MockNetworkMonitor()
            mockNetwork.isConnected = true
            EventManager.shared.networkMonitor = mockNetwork
        #endif
        try? Topsort.shared.configure(Configuration(apiKey: "test-key"))
    }

    func testConfigurationPassesDiscardCallbackThrough() {
        var config = Configuration(apiKey: "test-key")
        config.onEventsDiscarded = { _, _ in }
        XCTAssertNoThrow(try Topsort.shared.configure(config))
        XCTAssertNotNil(EventManager.shared.onEventsDiscarded)
    }

    override func tearDown() {
        Topsort.shared.isConfigured = true
        AuctionManager.shared.timeoutInterval = 60
        mockClient = nil
        super.tearDown()
    }

    // MARK: - OpaqueUserId

    func testOpaqueUserIdAutoGeneratesUUID() {
        Topsort.shared.set(opaqueUserId: nil)
        let uid = Topsort.shared.opaqueUserId
        XCTAssertFalse(uid.isEmpty)
        XCTAssertNotNil(UUID(uuidString: uid))
    }

    func testOpaqueUserIdPersistsAcrossAccess() {
        Topsort.shared.set(opaqueUserId: "custom-id")
        XCTAssertEqual(Topsort.shared.opaqueUserId, "custom-id")
        XCTAssertEqual(Topsort.shared.opaqueUserId, "custom-id")
    }

    func testSetOpaqueUserIdWithNilGeneratesNew() {
        Topsort.shared.set(opaqueUserId: "old-id")
        Topsort.shared.set(opaqueUserId: nil)
        let uid = Topsort.shared.opaqueUserId
        XCTAssertNotEqual(uid, "old-id")
        XCTAssertNotNil(UUID(uuidString: uid))
    }

    // MARK: - isConfigured guard (tests real Topsort.shared)

    // MARK: - Identity

    private var opaqueUserIdFileExists: Bool {
        FileManager.default.fileExists(atPath: PathHelper.path(for: "com.topsort.analytics.opaque-user-id.plist"))
    }

    func testEphemeralIdentityMintsAPerProcessIdAndWritesNothing() throws {
        Topsort.shared.set(opaqueUserId: "stored-id")
        wait(for: [expectation(for: NSPredicate { _, _ in self.opaqueUserIdFileExists }, evaluatedWith: nil)], timeout: 2)

        var config = Configuration(apiKey: "test-key")
        config.identity = .ephemeral
        try Topsort.shared.configure(config)

        let id = Topsort.shared.opaqueUserId
        XCTAssertNotEqual(id, "stored-id", "the stored id must not carry over")
        XCTAssertNotNil(UUID(uuidString: id))
        XCTAssertEqual(Topsort.shared.opaqueUserId, id, "stable within the process")
        wait(for: [expectation(for: NSPredicate { _, _ in !self.opaqueUserIdFileExists }, evaluatedWith: nil)], timeout: 2)

        Topsort.shared.set(opaqueUserId: "host-id")
        XCTAssertEqual(Topsort.shared.opaqueUserId, "host-id")
        XCTAssertFalse(opaqueUserIdFileExists, "a host id is honoured in memory only")
    }

    func testReconfiguringWhileEphemeralKeepsTheProcessId() throws {
        var config = Configuration(apiKey: "test-key")
        config.identity = .ephemeral
        try Topsort.shared.configure(config)
        let id = Topsort.shared.opaqueUserId
        try Topsort.shared.configure(config)
        XCTAssertEqual(Topsort.shared.opaqueUserId, id, "a token refresh must not split a session")
    }

    func testReturningToPersistedIdentityMintsAndStoresANewId() throws {
        var ephemeral = Configuration(apiKey: "test-key")
        ephemeral.identity = .ephemeral
        try Topsort.shared.configure(ephemeral)
        let ephemeralId = Topsort.shared.opaqueUserId

        try Topsort.shared.configure(Configuration(apiKey: "test-key"))
        let persisted = Topsort.shared.opaqueUserId
        XCTAssertNotEqual(persisted, ephemeralId)
        XCTAssertEqual(Topsort.shared.opaqueUserId, persisted)
        wait(for: [expectation(for: NSPredicate { _, _ in self.opaqueUserIdFileExists }, evaluatedWith: nil)], timeout: 2)
    }

    func testTrackDropsEventsWhenNotConfigured() {
        // Temporarily set Topsort.shared to unconfigured
        Topsort.shared.isConfigured = false

        Topsort.shared.set(opaqueUserId: "test-user")
        let event = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)
        Topsort.shared.track(impression: event)
        Topsort.shared.track(click: event)

        let purchase = PurchaseEvent(items: [PurchaseItem(productId: "p1", unitPrice: 5.0)], occurredAt: Date.now)
        Topsort.shared.track(purchase: purchase)

        // Wait briefly for any async dispatch
        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exp.fulfill() }
        wait(for: [exp], timeout: 2)

        // Events should have been dropped — mock client should NOT be called
        XCTAssertFalse(mockClient.postCalled, "Events should be dropped when not configured")
    }

    func testExecuteAuctionsThrowsWhenNotConfigured() async {
        Topsort.shared.isConfigured = false

        do {
            _ = try await Topsort.shared.executeAuctions(auctions: [Auction(type: "listings", slots: 1)])
            XCTFail("Should have thrown .notConfigured")
        } catch {
            if case .notConfigured = error {} else {
                XCTFail("Expected .notConfigured, got \(error)")
            }
        }
    }

    // MARK: - Configure

    func testConfigureSetsIsConfigured() {
        XCTAssertTrue(Topsort.shared.isConfigured)
    }

    func testConfigureWithCustomTimeout() throws {
        var config = Configuration(apiKey: "key")
        config.auctionsTimeout = 15
        try Topsort.shared.configure(config)
        XCTAssertEqual(AuctionManager.shared.timeoutInterval, 15)
    }

    func testConfigureWithValidURL() {
        var config = Configuration(apiKey: "key")
        config.url = "https://custom.api.com"
        XCTAssertNoThrow(try Topsort.shared.configure(config))
    }

    // MARK: - Track events after configure (integration)

    func testTrackImpressionReachesEventManager() {
        Topsort.shared.set(opaqueUserId: "test-user")
        let event = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)
        Topsort.shared.track(impression: event)
        Topsort.shared.flush()

        let predicate = NSPredicate { _, _ in self.mockClient.postCalled }
        let exp = expectation(for: predicate, evaluatedWith: nil)
        wait(for: [exp], timeout: 3)

        XCTAssertTrue(mockClient.postCalled)
    }

    func testTrackClickReachesEventManager() {
        Topsort.shared.set(opaqueUserId: "test-user")
        let event = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)
        Topsort.shared.track(click: event)
        Topsort.shared.flush()

        let predicate = NSPredicate { _, _ in self.mockClient.postCalled }
        let exp = expectation(for: predicate, evaluatedWith: nil)
        wait(for: [exp], timeout: 3)

        XCTAssertTrue(mockClient.postCalled)
    }

    func testTrackPurchaseReachesEventManager() {
        Topsort.shared.set(opaqueUserId: "test-user")
        let purchase = PurchaseEvent(items: [PurchaseItem(productId: "p1", unitPrice: 9.99)], occurredAt: Date.now)
        Topsort.shared.track(purchase: purchase)
        Topsort.shared.flush()

        let predicate = NSPredicate { _, _ in self.mockClient.postCalled }
        let exp = expectation(for: predicate, evaluatedWith: nil)
        wait(for: [exp], timeout: 3)

        XCTAssertTrue(mockClient.postCalled)
    }

    func testTrackPageviewReachesEventManager() throws {
        Topsort.shared.set(opaqueUserId: "test-user")
        Topsort.shared.track(pageview: PageViewEvent(page: Page(type: "category", pageId: "shoes"), occurredAt: Date.now))
        Topsort.shared.flush()

        wait(for: [expectation(for: NSPredicate { _, _ in self.mockClient.postCalled }, evaluatedWith: nil)], timeout: 3)

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(mockClient.postData)) as? [String: Any])
        let pageviews = try XCTUnwrap(json["pageviews"] as? [[String: Any]])
        XCTAssertEqual((pageviews.first?["page"] as? [String: Any])?["pageId"] as? String, "shoes")
    }

    // MARK: - Deprecated overload

    func testDeprecatedConfigureStillWorks() throws {
        Topsort.shared.isConfigured = false
        try Topsort.shared.configure(apiKey: "deprecated-key", auctionsTimeout: 25)
        XCTAssertTrue(Topsort.shared.isConfigured)
        XCTAssertEqual(AuctionManager.shared.timeoutInterval, 25)
    }

    // MARK: - Flush delegation

    func testFlushDelegatesToEventManager() {
        Topsort.shared.set(opaqueUserId: "test-user")
        let event = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)

        // Push without triggering auto-send (flushAt = 1 from setUp, so it will send)
        // Instead, verify flush() itself works by checking mock is called
        EventManager.shared._eventQueue = []
        mockClient = MockHTTPClient(apiKey: "test-key", postResult: .success(Data()))
        EventManager.shared.client = mockClient
        EventManager.shared.push(event: .impression(event))

        // Explicit flush
        Topsort.shared.flush()

        let predicate = NSPredicate { _, _ in self.mockClient.postCalled }
        let exp = expectation(for: predicate, evaluatedWith: nil)
        wait(for: [exp], timeout: 3)

        XCTAssertTrue(mockClient.postCalled)
    }
}
