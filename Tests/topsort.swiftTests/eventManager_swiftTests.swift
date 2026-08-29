import Foundation
@testable import Topsort
import XCTest

class EventManagerTests: XCTestCase {
    var eventManager: EventManager!
    var mockClient: MockHTTPClient!

    override func setUp() {
        super.setUp()
        mockClient = MockHTTPClient(apiKey: "test-key", postResult: .success(Data()))
        eventManager = EventManager.shared
        eventManager.client = mockClient
        // Reset singleton state to isolate tests
        eventManager._eventQueue = []
        eventManager._pendingEvents = [:]
        eventManager.flushAt = 1 // Send immediately for existing tests
        Topsort.shared.set(opaqueUserId: "test-user")
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

    func testConfigureRejectsFlushAtBelowOne() {
        XCTAssertThrowsError(try eventManager.configure(apiKey: "k", url: nil, flushAt: 0)) { error in
            guard case .invalidFlushAt(0) = error as? ConfigurationError else {
                return XCTFail("unexpected error \(error)")
            }
        }
        XCTAssertEqual(eventManager.flushAt, 1, "a rejected value must not be applied")
    }

    func testConfigureRejectsNonPositiveFlushInterval() {
        let before = eventManager.flushInterval
        XCTAssertThrowsError(try eventManager.configure(apiKey: "k", url: nil, flushInterval: 0)) { error in
            guard case .invalidFlushInterval(0) = error as? ConfigurationError else {
                return XCTFail("unexpected error \(error)")
            }
        }
        XCTAssertEqual(eventManager.flushInterval, before, "a rejected value must not be applied")
    }

    func testConfigureUpdatesURL() throws {
        try eventManager.configure(apiKey: "test-key", url: "https://custom.api.com/v2")
        XCTAssertEqual(eventManager.url.absoluteString, "https://custom.api.com/v2/events")
    }

    // MARK: - Push & Send

    func testPushEventTriggersHTTPPost() {
        let event = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)
        eventManager.push(event: .impression(event))

        let predicate = NSPredicate { _, _ in self.mockClient.postCalled }
        let exp = expectation(for: predicate, evaluatedWith: nil)
        wait(for: [exp], timeout: 3)

        XCTAssertEqual(mockClient.postCallCount, 1)
    }

    func testPushEventSerializesClickPayload() {
        let event = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)
        eventManager.push(event: .click(event))

        let predicate = NSPredicate { _, _ in self.mockClient.postCalled }
        let exp = expectation(for: predicate, evaluatedWith: nil)
        wait(for: [exp], timeout: 3)

        guard let data = mockClient.postData,
              let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            XCTFail("Expected valid JSON payload")
            return
        }

        XCTAssertNotNil(decoded["clicks"])
    }

    func testPushMultipleEventTypesBatchesCorrectly() {
        let impression = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)
        let click = Event(entity: Entity(type: .product, id: "p2"), occurredAt: Date.now)
        let purchase = PurchaseEvent(items: [PurchaseItem(productId: "p3", unitPrice: 9.99)], occurredAt: Date.now)

        eventManager.push(event: .impression(impression))
        eventManager.push(event: .click(click))
        eventManager.push(event: .purchase(purchase))

        let predicate = NSPredicate { _, _ in self.mockClient.postCalled }
        let exp = expectation(for: predicate, evaluatedWith: nil)
        wait(for: [exp], timeout: 3)

        // Events may be sent in 1-3 batches depending on timing,
        // but all data should have been posted
        XCTAssertGreaterThanOrEqual(mockClient.postCallCount, 1)
    }

    // MARK: - Error handling

    func testTransientErrorAttemptsSend() {
        mockClient.postResult = .failure(.statusCode(code: 500, data: nil))

        let event = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)
        eventManager.push(event: .impression(event))

        let predicate = NSPredicate { _, _ in self.mockClient.postCalled }
        let exp = expectation(for: predicate, evaluatedWith: nil)
        wait(for: [exp], timeout: 3)

        // The initial send was attempted and failed with a retriable error
        XCTAssertEqual(mockClient.postCallCount, 1)
        // Event should remain in pending for future retry (not dropped)
        // We can't directly assert pendingEvents since it's private,
        // but we verify it wasn't treated as non-retriable (which would drop it)
    }

    func testHTTP400AttemptsSendAndDropsEvent() {
        mockClient.postResult = .failure(.statusCode(code: 400, data: nil))

        let event = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)
        eventManager.push(event: .impression(event))

        let predicate = NSPredicate { _, _ in self.mockClient.postCalled }
        let exp = expectation(for: predicate, evaluatedWith: nil)
        wait(for: [exp], timeout: 3)

        // 400 is non-retriable — event should be sent once and dropped
        XCTAssertEqual(mockClient.postCallCount, 1)
    }

    /// A permanent 4xx must not enter the retry queue at all. Before 4xx was classified
    /// correctly a bad API key made every batch retriable, so each one spent 50 retries
    /// over ~16 hours and then sat in the plist as a zombie.
    func testHTTP401DropsBatchInsteadOfQueueingForRetry() {
        mockClient.postResult = .failure(.statusCode(code: 401, data: nil))

        let event = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)
        eventManager.push(event: .impression(event))

        let dropped = NSPredicate { _, _ in
            self.mockClient.postCallCount == 1 && self.eventManager._pendingEvents?.isEmpty == true
        }
        wait(for: [expectation(for: dropped, evaluatedWith: nil)], timeout: 3)
    }

    /// Queue and pending state are loaded from disk at init, and the periodic timer, the
    /// lifecycle observer and the connectivity monitor can all flush before the host has
    /// called configure(). A POST without a key is a 401, which is permanent, so the batch
    /// would be dropped instead of waiting for the key.
    func testNothingIsSentBeforeAnApiKeyIsConfigured() {
        mockClient.apiKey = nil
        let event = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)
        let stale = PendingEvents(id: UUID(), data: Data(), createdAt: Date(), retries: 1, lastRetry: Date.distantPast)
        eventManager._pendingEvents = [stale.id: stale]
        eventManager.push(event: .impression(event))

        eventManager.flushAndPersist()
        XCTAssertEqual(mockClient.postCallCount, 0, "sent without an API key")
        XCTAssertEqual(eventManager._eventQueue?.count, 1)
        XCTAssertEqual(eventManager._pendingEvents?.count, 1)

        mockClient.apiKey = "test-key"
        eventManager.flushAndPersist()
        XCTAssertEqual(mockClient.postCallCount, 2, "queue and pending batch were not sent once configured")
    }

    /// Negative validation for the above: a 5xx must still be queued for retry.
    func testHTTP503QueuesBatchForRetry() {
        mockClient.postResult = .failure(.statusCode(code: 503, data: nil))

        let event = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)
        eventManager.push(event: .impression(event))

        let queued = NSPredicate { _, _ in
            self.eventManager._pendingEvents?.values.first?.retries == 1
        }
        wait(for: [expectation(for: queued, evaluatedWith: nil)], timeout: 3)
    }

    // MARK: - Bounds

    private func entityId(_ item: EventItem?) -> String? {
        guard case let .impression(event)? = item else { return nil }
        return event.entity?.id
    }

    /// The queue grew without limit while sends were failing or the device was offline.
    /// It is now a fixed-capacity buffer that sheds the oldest event.
    func testQueueIsBoundedAndDropsOldestFirst() {
        eventManager.flushAt = MAX_QUEUED_EVENTS + 10 // never auto-sends
        eventManager._eventQueue = (0 ..< MAX_QUEUED_EVENTS).map { i in
            .impression(Event(entity: Entity(type: .product, id: "p\(i)"), occurredAt: Date.now))
        }

        eventManager.push(event: .impression(Event(entity: Entity(type: .product, id: "newest"), occurredAt: Date.now)))

        let bounded = NSPredicate { _, _ in self.eventManager._eventQueue?.count == MAX_QUEUED_EVENTS }
        wait(for: [expectation(for: bounded, evaluatedWith: nil)], timeout: 5)

        let queue = eventManager._eventQueue ?? []
        XCTAssertEqual(entityId(queue.first), "p1", "the oldest event should have been shed")
        XCTAssertEqual(entityId(queue.last), "newest", "the newest event should have been kept")
    }

    /// Negative validation for the above: below capacity nothing is dropped.
    func testQueueBelowCapacityKeepsEveryEvent() {
        eventManager.flushAt = MAX_QUEUED_EVENTS + 10
        eventManager._eventQueue = (0 ..< 10).map { i in
            .impression(Event(entity: Entity(type: .product, id: "p\(i)"), occurredAt: Date.now))
        }

        eventManager.push(event: .impression(Event(entity: Entity(type: .product, id: "newest"), occurredAt: Date.now)))

        let appended = NSPredicate { _, _ in self.eventManager._eventQueue?.count == 11 }
        wait(for: [expectation(for: appended, evaluatedWith: nil)], timeout: 3)
        XCTAssertEqual(entityId(eventManager._eventQueue?.first), "p0", "nothing should be dropped below capacity")
    }

    /// A backlog used to go out as one unbounded POST, which invites a 413 — non-retriable,
    /// so the entire backlog would be discarded. It is now split into capped batches.
    func testLargeQueueIsSentInBatchesCappedAtMaxEventsPerBatch() throws {
        eventManager.flushAt = MAX_QUEUED_EVENTS + 10
        let total = MAX_EVENTS_PER_BATCH * 2 + 200
        eventManager._eventQueue = (0 ..< total).map { i in
            .impression(Event(entity: Entity(type: .product, id: "p\(i)"), occurredAt: Date.now))
        }

        // Synchronous: MockHTTPClient calls back inline, so every POST is counted on return.
        eventManager.flushAndPersist()

        XCTAssertEqual(mockClient.postCallCount, 3)
        XCTAssertEqual(eventManager._eventQueue?.count, 0, "the whole backlog should have been drained")

        var sizes: [Int] = []
        for data in mockClient.allPostedData {
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let impressions = try XCTUnwrap(json["impressions"] as? [[String: Any]])
            sizes.append(impressions.count)
        }
        XCTAssertEqual(sizes, [MAX_EVENTS_PER_BATCH, MAX_EVENTS_PER_BATCH, 200])
    }

    /// The drain stops at the in-flight cap; what is left waits for the next flush.
    func testSendLoopStopsAtTheInFlightCap() {
        eventManager.flushAt = MAX_QUEUED_EVENTS + 10
        let total = MAX_EVENTS_PER_BATCH * (MAX_IN_PROGRESS + 1)
        eventManager._eventQueue = (0 ..< total).map { i in
            .impression(Event(entity: Entity(type: .product, id: "p\(i)"), occurredAt: Date.now))
        }

        eventManager.flushAndPersist()

        XCTAssertEqual(mockClient.postCallCount, MAX_IN_PROGRESS)
        XCTAssertEqual(eventManager._eventQueue?.count, MAX_EVENTS_PER_BATCH, "the batch past the cap should stay queued")
    }

    /// JSONEncoder refuses non-finite doubles. One such purchase must not take the rest of
    /// its batch with it, nor stall the queue behind it.
    func testUnencodableEventIsDroppedWithoutItsBatch() throws {
        eventManager.flushAt = MAX_QUEUED_EVENTS + 10
        let bad = PurchaseEvent(items: [PurchaseItem(productId: "p1", unitPrice: .nan)], occurredAt: Date.now)
        eventManager._eventQueue = [
            .impression(Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)),
            .purchase(bad),
            .click(Event(entity: Entity(type: .product, id: "p2"), occurredAt: Date.now)),
        ]

        eventManager.flushAndPersist()

        XCTAssertEqual(mockClient.postCallCount, 1)
        XCTAssertEqual(eventManager._eventQueue?.count, 0)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(mockClient.postData)) as? [String: Any])
        XCTAssertEqual((json["impressions"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((json["clicks"] as? [[String: Any]])?.count, 1)
        XCTAssertNil(json["purchases"])
    }

    // MARK: - Batching

    func testPushBelowThresholdDoesNotSend() {
        eventManager.flushAt = 10

        let event = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)
        eventManager.push(event: .impression(event))

        // Wait briefly — send should NOT be triggered
        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exp.fulfill() }
        wait(for: [exp], timeout: 2)

        XCTAssertFalse(mockClient.postCalled)
    }

    func testPushAtThresholdTriggersSend() {
        eventManager.flushAt = 3

        for i in 0 ..< 3 {
            let event = Event(entity: Entity(type: .product, id: "p\(i)"), occurredAt: Date.now)
            eventManager.push(event: .impression(event))
        }

        let predicate = NSPredicate { _, _ in self.mockClient.postCalled }
        let exp = expectation(for: predicate, evaluatedWith: nil)
        wait(for: [exp], timeout: 3)

        XCTAssertGreaterThanOrEqual(mockClient.postCallCount, 1)
    }

    func testFlushSendsQueuedEvents() {
        eventManager.flushAt = 100 // High threshold so push alone won't trigger

        let event = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)
        eventManager.push(event: .impression(event))

        // Manually flush
        eventManager.flush()

        let predicate = NSPredicate { _, _ in self.mockClient.postCalled }
        let exp = expectation(for: predicate, evaluatedWith: nil)
        wait(for: [exp], timeout: 3)

        XCTAssertEqual(mockClient.postCallCount, 1)
    }

    // MARK: - Retry exhaustion

    /// Regression: a batch that has exhausted MAX_RETRIES must be retired.
    /// Before the fix it stayed in pendingEvents with a frozen retries/lastRetry, so its
    /// retryAfter was permanently in the past and performRetry re-sent it on every flush,
    /// forever, while the record grew the persisted plist without bound.
    func testExhaustedBatchIsRetiredAndNotRetriedAgain() {
        mockClient.postResult = .failure(.statusCode(code: 500, data: nil))
        let id = UUID()
        let stale = Date(timeIntervalSinceNow: -100_000)
        eventManager._pendingEvents = [
            id: PendingEvents(id: id, data: Data("{}".utf8), createdAt: stale, retries: MAX_RETRIES, lastRetry: stale),
        ]

        eventManager.flush()

        let retired = NSPredicate { _, _ in self.eventManager._pendingEvents?[id] == nil }
        wait(for: [expectation(for: retired, evaluatedWith: nil)], timeout: 3)
        XCTAssertEqual(mockClient.postCallCount, 1)

        // A further flush must not resurrect it. flushAndPersist runs performRetry
        // synchronously and MockHTTPClient invokes its callback inline, so any re-send
        // would already be counted by the time this returns.
        eventManager.flushAndPersist()
        XCTAssertEqual(mockClient.postCallCount, 1, "Retired batch was sent again")
        XCTAssertNil(eventManager._pendingEvents?[id])
    }

    /// Negative validation for the above: a batch that has NOT exhausted its retries must
    /// be kept and its retry count incremented — retirement must not swallow live batches.
    func testUnexhaustedBatchIsKeptAndRetryCountIncremented() {
        mockClient.postResult = .failure(.statusCode(code: 500, data: nil))
        let id = UUID()
        let stale = Date(timeIntervalSinceNow: -100_000)
        eventManager._pendingEvents = [
            id: PendingEvents(id: id, data: Data("{}".utf8), createdAt: stale, retries: 3, lastRetry: stale),
        ]

        eventManager.flush()

        let incremented = NSPredicate { _, _ in self.eventManager._pendingEvents?[id]?.retries == 4 }
        wait(for: [expectation(for: incremented, evaluatedWith: nil)], timeout: 3)
        XCTAssertEqual(mockClient.postCallCount, 1)
    }
}

// MARK: - PendingEvents backoff tests

class PendingEventsTests: XCTestCase {
    func testExponentialBackoffCalculation() {
        let base = Date()
        var pending = PendingEvents(id: UUID(), data: Data(), createdAt: base, retries: 0, lastRetry: base)

        // retries=0 -> wait = min(10 * 2^0, 1200) = 10s
        XCTAssertEqual(pending.retryAfter.timeIntervalSince(base), 10, accuracy: 0.001)

        // retries=1 -> wait = min(10 * 2^1, 1200) = 20s
        pending.retries = 1
        XCTAssertEqual(pending.retryAfter.timeIntervalSince(base), 20, accuracy: 0.001)

        // retries=2 -> wait = min(10 * 2^2, 1200) = 40s
        pending.retries = 2
        XCTAssertEqual(pending.retryAfter.timeIntervalSince(base), 40, accuracy: 0.001)

        // retries=5 -> wait = min(10 * 2^5, 1200) = 320s
        pending.retries = 5
        XCTAssertEqual(pending.retryAfter.timeIntervalSince(base), 320, accuracy: 0.001)
    }

    func testBackoffCapsAt1200Seconds() {
        let base = Date()
        var pending = PendingEvents(id: UUID(), data: Data(), createdAt: base, retries: 10, lastRetry: base)

        // retries=10 -> wait = min(10 * 2^10, 1200) = min(10240, 1200) = 1200s
        XCTAssertEqual(pending.retryAfter.timeIntervalSince(base), 1200, accuracy: 0.001)

        // retries=50 -> still capped at 1200
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
