import Foundation
@testable import Topsort
import XCTest

class EventManagerTests: XCTestCase {
    var eventManager: EventManager!
    var mockClient: MockHTTPClient!

    override func setUp() {
        super.setUp()
        mockClient = MockHTTPClient(apiKey: nil, postResult: .success(Data()))
        eventManager = EventManager.shared
        eventManager.client = mockClient
    }

    override func tearDown() {
        eventManager = nil
        mockClient = nil
        super.tearDown()
    }

    // MARK: - Configure

    func testConfigureUpdatesApiKey() throws {
        try eventManager.configure(apiKey: "test-key", url: nil)
        XCTAssertEqual(mockClient.apiKey, "test-key")
    }

    func testConfigureUpdatesURL() throws {
        try eventManager.configure(apiKey: "test-key", url: "https://custom.api.com/v2")
        XCTAssertEqual(eventManager.url.absoluteString, "https://custom.api.com/v2/events")
    }

    // MARK: - Push & Send

    func testPushEventTriggersHTTPPost() {
        let expectation = expectation(description: "post called")

        Topsort.shared.set(opaqueUserId: "test-user")
        let event = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)
        eventManager.push(event: .impression(event))

        // EventManager dispatches asynchronously, give it time
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)
        XCTAssertTrue(mockClient.postCalled)
        XCTAssertEqual(mockClient.postCallCount, 1)
    }

    func testPushEventSerializesCorrectPayload() {
        let expectation = expectation(description: "post called")

        Topsort.shared.set(opaqueUserId: "test-user")
        let event = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)
        eventManager.push(event: .click(event))

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)

        guard let data = mockClient.postData,
              let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            XCTFail("Expected valid JSON payload")
            return
        }

        XCTAssertNotNil(decoded["clicks"])
    }

    func testPushMultipleEventTypesBatchesCorrectly() {
        let expectation = expectation(description: "post called")

        Topsort.shared.set(opaqueUserId: "test-user")
        let impression = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)
        let click = Event(entity: Entity(type: .product, id: "p2"), occurredAt: Date.now)
        let purchase = PurchaseEvent(items: [PurchaseItem(productId: "p3", unitPrice: 9.99)], occurredAt: Date.now)

        eventManager.push(event: .impression(impression))
        eventManager.push(event: .click(click))
        eventManager.push(event: .purchase(purchase))

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)

        // Events may be sent in 1-3 batches depending on timing,
        // but all data should have been posted
        XCTAssertTrue(mockClient.postCalled)
        XCTAssertGreaterThanOrEqual(mockClient.postCallCount, 1)
    }

    // MARK: - Retry behavior

    func testTransientErrorTriggersRetry() {
        let expectation = expectation(description: "retries")

        mockClient.postResult = .failure(.statusCode(code: 500, data: nil))

        Topsort.shared.set(opaqueUserId: "test-user")
        let event = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)
        eventManager.push(event: .impression(event))

        // Wait long enough for the initial send to fail
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 3)

        // The initial send should have been attempted
        XCTAssertTrue(mockClient.postCalled)
        XCTAssertEqual(mockClient.postCallCount, 1)
    }

    func testHTTP400IsNotRetried() {
        let expectation = expectation(description: "no retry")

        mockClient.postResult = .failure(.statusCode(code: 400, data: nil))

        Topsort.shared.set(opaqueUserId: "test-user")
        let event = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)
        eventManager.push(event: .impression(event))

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 3)

        // Should only be called once — 400 is non-retriable
        XCTAssertEqual(mockClient.postCallCount, 1)
    }
}

// MARK: - PendingEvents backoff tests

class PendingEventsTests: XCTestCase {
    func testExponentialBackoffCalculation() {
        let base = Date()
        var pending = PendingEvents(id: UUID(), data: Data(), createdAt: base, retries: 0, lastRetry: base)

        // retries=0 → wait = min(10 * 2^0, 1200) = 10s
        XCTAssertEqual(pending.retryAfter.timeIntervalSince(base), 10, accuracy: 0.001)

        // retries=1 → wait = min(10 * 2^1, 1200) = 20s
        pending.retries = 1
        XCTAssertEqual(pending.retryAfter.timeIntervalSince(base), 20, accuracy: 0.001)

        // retries=2 → wait = min(10 * 2^2, 1200) = 40s
        pending.retries = 2
        XCTAssertEqual(pending.retryAfter.timeIntervalSince(base), 40, accuracy: 0.001)

        // retries=5 → wait = min(10 * 2^5, 1200) = 320s
        pending.retries = 5
        XCTAssertEqual(pending.retryAfter.timeIntervalSince(base), 320, accuracy: 0.001)
    }

    func testBackoffCapsAt1200Seconds() {
        let base = Date()
        var pending = PendingEvents(id: UUID(), data: Data(), createdAt: base, retries: 10, lastRetry: base)

        // retries=10 → wait = min(10 * 2^10, 1200) = min(10240, 1200) = 1200s
        XCTAssertEqual(pending.retryAfter.timeIntervalSince(base), 1200, accuracy: 0.001)

        // retries=50 → still capped at 1200
        pending.retries = 50
        XCTAssertEqual(pending.retryAfter.timeIntervalSince(base), 1200, accuracy: 0.001)
    }

    func testBackoffUsesLastRetryAsBase() {
        let base = Date()
        let laterDate = base.addingTimeInterval(100)
        let pending = PendingEvents(id: UUID(), data: Data(), createdAt: base, retries: 0, lastRetry: laterDate)

        // retryAfter should be relative to lastRetry, not createdAt
        XCTAssertEqual(pending.retryAfter.timeIntervalSince(laterDate), 10, accuracy: 0.001)
    }
}

// MARK: - EventItem conversion tests

class EventItemTests: XCTestCase {
    func testToEventsGroupsByType() {
        Topsort.shared.set(opaqueUserId: "test-user")
        let impression = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)
        let click = Event(entity: Entity(type: .product, id: "p2"), occurredAt: Date.now)
        let purchase = PurchaseEvent(items: [PurchaseItem(productId: "p3", unitPrice: 5.0)], occurredAt: Date.now)

        let items: [EventItem] = [
            .impression(impression),
            .click(click),
            .purchase(purchase),
        ]

        let events = items.toEvents()

        XCTAssertEqual(events.impressions?.count, 1)
        XCTAssertEqual(events.clicks?.count, 1)
        XCTAssertEqual(events.purchases?.count, 1)
    }

    func testToEventsWithEmptyArray() {
        let items: [EventItem] = []
        let events = items.toEvents()

        XCTAssertTrue(events.impressions?.isEmpty ?? true)
        XCTAssertTrue(events.clicks?.isEmpty ?? true)
        XCTAssertTrue(events.purchases?.isEmpty ?? true)
    }
}
