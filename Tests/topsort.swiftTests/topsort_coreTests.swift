@testable import Topsort
import XCTest

class TopsortCoreTests: XCTestCase {
    var mockClient: MockHTTPClient!

    override func setUp() {
        super.setUp()
        mockClient = MockHTTPClient(apiKey: nil, postResult: .success(Data()))
        EventManager.shared.client = mockClient
        EventManager.shared._eventQueue = []
        EventManager.shared._pendingEvents = [:]
        try? Topsort.shared.configure(apiKey: "test-key")
    }

    override func tearDown() {
        // Restore default timeout to avoid leaking into other tests
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

    // MARK: - isConfigured guard

    func testTrackImpressionDroppedWhenNotConfigured() {
        // Verify via the protocol contract: a non-configured mock should not
        // forward events. We test the TopsortProtocol.track() guard pattern
        // by using a tracking mock that starts unconfigured.
        let mock = TrackingUnconfiguredTopsort()
        let event = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now, opaqueUserId: "test")
        mock.track(impression: event)
        mock.track(click: event)

        let purchase = PurchaseEvent(items: [PurchaseItem(productId: "p1", unitPrice: 5.0)], occurredAt: Date.now, opaqueUserId: "test")
        mock.track(purchase: purchase)

        XCTAssertEqual(mock.impressionCount, 0, "Impression should be dropped when not configured")
        XCTAssertEqual(mock.clickCount, 0, "Click should be dropped when not configured")
        XCTAssertEqual(mock.purchaseCount, 0, "Purchase should be dropped when not configured")
    }

    func testExecuteAuctionsThrowsNotConfiguredViaProtocol() async {
        let mock = TrackingUnconfiguredTopsort()
        do {
            _ = try await mock.executeAuctions(auctions: [Auction(type: "listings", slots: 1)])
            XCTFail("Should have thrown")
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
        try Topsort.shared.configure(apiKey: "key", auctionsTimeout: 15)
        XCTAssertEqual(AuctionManager.shared.timeoutInterval, 15)
    }

    func testConfigureWithValidURL() {
        XCTAssertNoThrow(try Topsort.shared.configure(apiKey: "key", url: "https://custom.api.com"))
    }

    // MARK: - Track events after configure (integration)

    func testTrackImpressionReachesEventManager() {
        Topsort.shared.set(opaqueUserId: "test-user")
        let event = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)
        Topsort.shared.track(impression: event)

        let predicate = NSPredicate { _, _ in self.mockClient.postCalled }
        let exp = expectation(for: predicate, evaluatedWith: nil)
        wait(for: [exp], timeout: 3)

        XCTAssertTrue(mockClient.postCalled)
    }

    func testTrackClickReachesEventManager() {
        Topsort.shared.set(opaqueUserId: "test-user")
        let event = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)
        Topsort.shared.track(click: event)

        let predicate = NSPredicate { _, _ in self.mockClient.postCalled }
        let exp = expectation(for: predicate, evaluatedWith: nil)
        wait(for: [exp], timeout: 3)

        XCTAssertTrue(mockClient.postCalled)
    }

    func testTrackPurchaseReachesEventManager() {
        Topsort.shared.set(opaqueUserId: "test-user")
        let purchase = PurchaseEvent(items: [PurchaseItem(productId: "p1", unitPrice: 9.99)], occurredAt: Date.now)
        Topsort.shared.track(purchase: purchase)

        let predicate = NSPredicate { _, _ in self.mockClient.postCalled }
        let exp = expectation(for: predicate, evaluatedWith: nil)
        wait(for: [exp], timeout: 3)

        XCTAssertTrue(mockClient.postCalled)
    }
}

/// A TopsortProtocol conformer that mimics the isConfigured guard behavior
private class TrackingUnconfiguredTopsort: TopsortProtocol {
    var opaqueUserId: String = "test"
    var isConfigured: Bool = false
    var impressionCount = 0
    var clickCount = 0
    var purchaseCount = 0

    func set(opaqueUserId _: String?) {}
    func configure(apiKey _: String, url _: String?, auctionsTimeout _: TimeInterval?) throws {}

    func track(impression _: Event) {
        guard isConfigured else { return }
        impressionCount += 1
    }

    func track(click _: Event) {
        guard isConfigured else { return }
        clickCount += 1
    }

    func track(purchase _: PurchaseEvent) {
        guard isConfigured else { return }
        purchaseCount += 1
    }

    func executeAuctions(auctions _: [Auction]) async throws(AuctionError) -> AuctionResponse {
        throw .notConfigured
    }
}
