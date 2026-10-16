@testable import Topsort
import XCTest

class ReportedBidsTests: XCTestCase {
    func testFirstReportPassesAndRepeatIsCaught() {
        let bids = ReportedBids()
        XCTAssertTrue(bids.markReported("bid-1", for: "user-1"))
        XCTAssertFalse(bids.markReported("bid-1", for: "user-1"))
        XCTAssertTrue(bids.markReported("bid-2", for: "user-1"), "other bids are unaffected")
    }

    func testOnlyTheFirstRepeatIsReportedAsFirst() {
        let bids = ReportedBids()
        XCTAssertTrue(bids.isFirstRepeat())
        XCTAssertFalse(bids.isFirstRepeat())
        bids.clear()
        XCTAssertTrue(bids.isFirstRepeat(), "clear starts over")
    }

    func testConcurrentRepeatsSeeExactlyOneFirst() {
        let bids = ReportedBids()
        let lock = NSLock()
        var firsts = 0
        DispatchQueue.concurrentPerform(iterations: 1000) { _ in
            if bids.isFirstRepeat() {
                lock.withLock { firsts += 1 }
            }
        }
        XCTAssertEqual(firsts, 1)
    }

    func testTheSameBidForAnotherUserIsNotARepeat() {
        let bids = ReportedBids()
        XCTAssertTrue(bids.markReported("bid-1", for: "user-1"))
        XCTAssertTrue(bids.markReported("bid-1", for: "user-2"))
        XCTAssertFalse(bids.markReported("bid-1", for: "user-1"))
    }

    func testClearForgetsEveryBid() {
        let bids = ReportedBids()
        _ = bids.markReported("bid-1", for: "user-1")
        bids.clear()
        XCTAssertTrue(bids.markReported("bid-1", for: "user-1"))
    }

    func testPastCapacityTheLeastRecentlyReportedBidIsForgotten() {
        let bids = ReportedBids(capacity: 2)
        _ = bids.markReported("a", for: "user-1")
        _ = bids.markReported("b", for: "user-1")
        XCTAssertFalse(bids.markReported("a", for: "user-1"), "a repeat makes a the most recent")
        _ = bids.markReported("c", for: "user-1")
        XCTAssertFalse(bids.markReported("a", for: "user-1"), "a was reported more recently than b")
        XCTAssertTrue(bids.markReported("b", for: "user-1"), "b was the least recent, so c evicted it")
    }

    func testAtTheRealCapacityARepeatedBidOutlivesNewerOnes() {
        let bids = ReportedBids()
        _ = bids.markReported("kept", for: "user-1")
        _ = bids.markReported("evicted", for: "user-1")
        for i in 0 ..< ReportedBids.defaultCapacity - 2 {
            _ = bids.markReported("filler-\(i)", for: "user-1")
        }
        XCTAssertFalse(bids.markReported("kept", for: "user-1"), "full, nothing evicted yet")
        _ = bids.markReported("one-past-capacity", for: "user-1")
        XCTAssertFalse(bids.markReported("kept", for: "user-1"), "the repeat made kept recent")
        XCTAssertTrue(bids.markReported("evicted", for: "user-1"), "the least recent went first")
    }

    func testUnmarkForgetsOneReportOnly() {
        let bids = ReportedBids()
        _ = bids.markReported("bid-1", for: "user-1")
        _ = bids.markReported("bid-1", for: "user-2")
        bids.unmark("bid-1", for: "user-1")
        bids.unmark("never-reported", for: "user-1")
        XCTAssertTrue(bids.markReported("bid-1", for: "user-1"))
        XCTAssertFalse(bids.markReported("bid-1", for: "user-2"))
    }

    func testClearThenReportStartsAFreshOrder() {
        let bids = ReportedBids(capacity: 2)
        _ = bids.markReported("a", for: "user-1")
        _ = bids.markReported("b", for: "user-1")
        bids.clear()
        XCTAssertTrue(bids.markReported("c", for: "user-1"))
        XCTAssertTrue(bids.markReported("d", for: "user-1"))
        XCTAssertFalse(bids.markReported("c", for: "user-1"))
        XCTAssertTrue(bids.markReported("e", for: "user-1"), "evicts d, the least recent")
        XCTAssertTrue(bids.markReported("d", for: "user-1"))
    }

    /// Random reports checked against a plain array kept in recency order, the obvious LRU, so
    /// every unlink and relink path of the list is exercised, including capacity 1.
    func testMatchesAnArrayLRUOnRandomReports() {
        var rng = SystemRandomNumberGenerator()
        for capacity in [1, 2, 3, 8] {
            let bids = ReportedBids(capacity: capacity)
            var model: [String] = []
            for step in 0 ..< 5000 {
                let bid = "bid-\(Int.random(in: 0 ..< capacity * 2 + 1, using: &rng))"
                if Int.random(in: 0 ..< 5, using: &rng) == 0 {
                    model.removeAll { $0 == bid }
                    bids.unmark(bid, for: "user-1")
                    continue
                }
                let expected: Bool
                if let index = model.firstIndex(of: bid) {
                    model.remove(at: index)
                    expected = false
                } else {
                    expected = true
                }
                model.append(bid)
                if model.count > capacity {
                    model.removeFirst()
                }
                XCTAssertEqual(bids.markReported(bid, for: "user-1"), expected, "capacity \(capacity), step \(step), \(bid)")
            }
        }
    }

    func testConcurrentReportsOfOneBidLetExactlyOneThrough() {
        let bids = ReportedBids()
        let lock = NSLock()
        var firsts = 0
        DispatchQueue.concurrentPerform(iterations: 1000) { _ in
            if bids.markReported("bid-1", for: "user-1") {
                lock.withLock { firsts += 1 }
            }
        }
        XCTAssertEqual(firsts, 1)
    }
}

/// Repeat reports through the `Topsort.shared` facade, read back from the event queue. The
/// network is down so nothing leaves the queue while a test inspects it.
class TopsortRepeatReportTests: XCTestCase {
    private var originalClient: HTTPClient!
    #if canImport(Network)
        private var originalNetworkMonitor: NetworkMonitoring!
    #endif

    override func setUp() {
        super.setUp()
        originalClient = EventManager.shared.client
        EventManager.shared.client = MockHTTPClient(apiKey: "test-key", postResult: .success(Data()))
        #if canImport(Network)
            originalNetworkMonitor = EventManager.shared.networkMonitor
            let mockNetwork = MockNetworkMonitor()
            mockNetwork.isConnected = false
            EventManager.shared.networkMonitor = mockNetwork
        #endif
        try? Topsort.shared.configure(Configuration(apiKey: "test-key"))
        EventManager.shared.flushAt = 10000
        // Let pushes an earlier suite left in flight land before the queue is emptied.
        EventManager.shared.flushAndPersist()
        EventManager.shared._eventQueue = []
        EventManager.shared._pendingEvents = [:]
        Topsort.shared.reportedImpressionBids.clear()
        Topsort.shared.reportedRenderBids.clear()
    }

    override func tearDown() {
        Topsort.shared.isConfigured = true
        // Back to the default flush threshold, for the suites that follow.
        try? Topsort.shared.configure(Configuration(apiKey: "test-key"))
        EventManager.shared.flushAndPersist()
        EventManager.shared._eventQueue = []
        EventManager.shared._pendingEvents = [:]
        EventManager.shared.client = originalClient
        #if canImport(Network)
            EventManager.shared.networkMonitor = originalNetworkMonitor
        #endif
        super.tearDown()
    }

    /// Everything tracked before this call. `push` is asynchronous on the event manager's serial
    /// queue; `flushAndPersist` runs synchronously on that queue, after every earlier push, and
    /// sends nothing while the network is down.
    private func queued() -> [EventItem] {
        EventManager.shared.flushAndPersist()
        return EventManager.shared._eventQueue ?? []
    }

    private func count(_ kind: EventItemKind, in items: [EventItem]) -> Int {
        items.filter { $0.kind == kind }.count
    }

    /// Every event names its user. The initializers' default reads `Topsort.shared`'s id, which
    /// mints and stores one on disk; these tests leave the shared identity alone.
    private func impression(bid: String, user: String = "user-1") -> Event {
        Event(resolvedBidId: bid, occurredAt: Date.now, opaqueUserId: user)
    }

    private func render(bid: String, user: String = "user-1") -> RenderEvent {
        RenderEvent(resolvedBidId: bid, occurredAt: Date.now, opaqueUserId: user)
    }

    func testRepeatPromotedImpressionIsDropped() {
        Topsort.shared.track(impression: impression(bid: "bid-1"))
        Topsort.shared.track(impression: impression(bid: "bid-1"))
        Topsort.shared.track(impression: impression(bid: "bid-2"))
        XCTAssertEqual(count(.impression, in: queued()), 2)
    }

    func testRepeatRenderIsDropped() {
        Topsort.shared.track(render: render(bid: "bid-1"))
        Topsort.shared.track(render: render(bid: "bid-1"))
        XCTAssertEqual(count(.render, in: queued()), 1)
    }

    func testRenderDoesNotUseUpTheImpressionOfItsBid() {
        Topsort.shared.track(render: render(bid: "bid-1"))
        Topsort.shared.track(impression: impression(bid: "bid-1"))
        let items = queued()
        XCTAssertEqual(count(.render, in: items), 1)
        XCTAssertEqual(count(.impression, in: items), 1)
    }

    func testOrganicImpressionsAndClicksAreNeverDropped() {
        let organic = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now, opaqueUserId: "user-1")
        Topsort.shared.track(impression: organic)
        Topsort.shared.track(impression: organic)
        Topsort.shared.track(click: impression(bid: "bid-1"))
        Topsort.shared.track(click: impression(bid: "bid-1"))
        let items = queued()
        XCTAssertEqual(count(.impression, in: items), 2)
        XCTAssertEqual(count(.click, in: items), 2)
    }

    func testImpressionDroppedBeforeConfigureDoesNotCountAsReported() {
        Topsort.shared.isConfigured = false
        Topsort.shared.track(impression: impression(bid: "bid-1"))
        Topsort.shared.isConfigured = true
        Topsort.shared.track(impression: impression(bid: "bid-1"))
        XCTAssertEqual(count(.impression, in: queued()), 1)
    }

    /// An event the API would reject is dropped and never sent, so it must not use up its bid: the
    /// corrected report that follows is the first real one.
    func testAnInvalidReportDoesNotUseUpItsBid() {
        let invalid = Event(resolvedBidId: "bid-1", occurredAt: Date.now, opaqueUserId: "user-1", placement: Placement(path: "/home", position: 0))
        Topsort.shared.track(impression: invalid)
        Topsort.shared.track(impression: impression(bid: "bid-1"))
        Topsort.shared.track(render: RenderEvent(resolvedBidId: "bid-1", occurredAt: Date.now, opaqueUserId: "user-1", id: ""))
        Topsort.shared.track(render: render(bid: "bid-1"))
        let items = queued()
        XCTAssertEqual(count(.impression, in: items), 1)
        XCTAssertEqual(count(.render, in: items), 1)
        XCTAssertNil(items.first { $0.specViolation != nil }, "only the valid reports are queued")
    }

    /// An invalid repeat must not free a bid a valid report already used.
    func testAnInvalidRepeatDoesNotFreeItsBid() {
        Topsort.shared.track(impression: impression(bid: "bid-1"))
        Topsort.shared.track(impression: Event(resolvedBidId: "bid-1", occurredAt: Date.now, opaqueUserId: "user-1", id: ""))
        Topsort.shared.track(impression: impression(bid: "bid-1"))
        XCTAssertEqual(count(.impression, in: queued()), 1)
    }

    /// A shared device or kiosk passes each user's id on the event and never changes the
    /// facade's: each user's report of the bid is their own.
    func testEachUsersReportOfTheSameBidIsSent() {
        for user in ["user-a", "user-b", "user-a"] {
            Topsort.shared.track(impression: impression(bid: "bid-1", user: user))
            Topsort.shared.track(render: render(bid: "bid-1", user: user))
        }
        let items = queued()
        XCTAssertEqual(count(.impression, in: items), 2, "user-a's second report is a repeat")
        XCTAssertEqual(count(.render, in: items), 2)
    }

    // MARK: - Reports the queue gave up on

    /// A send and its response each run as their own block on the event manager's serial queue,
    /// the response enqueued while the send runs, so it takes two barriers to see it applied.
    private func drain() {
        EventManager.shared.flushAndPersist()
        EventManager.shared.flushAndPersist()
    }

    private func promotedImpressions(of bid: String, in items: [EventItem]) -> Int {
        items.filter { item in
            if case let .impression(event) = item {
                return event.resolvedBidId == bid
            }
            return false
        }.count
    }

    func testAnImpressionEvictedFromAFullQueueCanBeReportedAgain() {
        Topsort.shared.track(impression: impression(bid: "bid-1"))
        let filler = EventItem.impression(Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now, opaqueUserId: "user-1"))
        EventManager.shared._eventQueue = queued() + Array(repeating: filler, count: MAX_QUEUED_EVENTS)
        EventManager.shared.push(event: filler) // past capacity: the oldest, bid-1's impression, is evicted
        EventManager.shared.flushAndPersist() // the eviction has run
        Topsort.shared.track(impression: impression(bid: "bid-1"))
        XCTAssertEqual(promotedImpressions(of: "bid-1", in: queued()), 1)
    }

    #if canImport(Network)
        private func goOnline(failingWith statusCode: Int) -> MockHTTPClient {
            let client = MockHTTPClient(apiKey: "test-key", postResult: .failure(.statusCode(code: statusCode, data: nil)))
            EventManager.shared.client = client
            let online = MockNetworkMonitor()
            online.isConnected = true
            EventManager.shared.networkMonitor = online
            return client
        }

        func testAnImpressionTheAPIRejectedCanBeReportedAgain() {
            let client = goOnline(failingWith: 400)
            EventManager.shared.flushAt = 1
            Topsort.shared.track(impression: impression(bid: "bid-1"))
            drain()
            Topsort.shared.track(impression: impression(bid: "bid-1"))
            drain()
            XCTAssertEqual(client.postCallCount, 2, "the rejected report was forgotten, so the second one is sent")
        }

        func testAnImpressionWhoseRetriesRanOutCanBeReportedAgain() throws {
            XCTAssertTrue(Topsort.shared.reportedImpressionBids.markReported("bid-1", for: "user-1"))
            let client = goOnline(failingWith: 500)
            let id = UUID()
            let stale = Date(timeIntervalSinceNow: -100_000)
            let body = try JSONEncoder().encode(Events(impressions: [impression(bid: "bid-1")]))
            EventManager.shared._pendingEvents = [id: PendingEvents(id: id, data: body, createdAt: stale, retries: MAX_RETRIES, lastRetry: stale)]
            drain()
            XCTAssertEqual(client.postCallCount, 1)
            XCTAssertTrue(Topsort.shared.reportedImpressionBids.markReported("bid-1", for: "user-1"), "the retired batch's bid was forgotten")
        }
    #endif
}
