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
