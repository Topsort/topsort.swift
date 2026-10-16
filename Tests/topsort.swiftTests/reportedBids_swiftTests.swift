@testable import Topsort
import XCTest

class ReportedBidsTests: XCTestCase {
    func testFirstReportPassesAndRepeatIsCaught() {
        let bids = ReportedBids()
        XCTAssertTrue(bids.markReported("bid-1"))
        XCTAssertFalse(bids.markReported("bid-1"))
        XCTAssertTrue(bids.markReported("bid-2"), "other bids are unaffected")
    }

    func testClearForgetsEveryBid() {
        let bids = ReportedBids()
        _ = bids.markReported("bid-1")
        bids.clear()
        XCTAssertTrue(bids.markReported("bid-1"))
    }

    func testPastCapacityTheLeastRecentlyReportedBidIsForgotten() {
        let bids = ReportedBids(capacity: 2)
        _ = bids.markReported("a")
        _ = bids.markReported("b")
        XCTAssertFalse(bids.markReported("a"), "a repeat makes a the most recent")
        _ = bids.markReported("c")
        XCTAssertFalse(bids.markReported("a"), "a was reported more recently than b")
        XCTAssertTrue(bids.markReported("b"), "b was the least recent, so c evicted it")
    }
}

/// Repeat reports through the `Topsort.shared` facade, read back from the event queue. The
/// network is down so nothing leaves the queue while a test inspects it.
class TopsortRepeatReportTests: XCTestCase {
    override func setUp() {
        super.setUp()
        EventManager.shared.client = MockHTTPClient(apiKey: "test-key", postResult: .success(Data()))
        #if canImport(Network)
            let mockNetwork = MockNetworkMonitor()
            mockNetwork.isConnected = false
            EventManager.shared.networkMonitor = mockNetwork
        #endif
        try? Topsort.shared.configure(Configuration(apiKey: "test-key"))
        EventManager.shared.flushAt = 10000
        EventManager.shared._eventQueue = []
        Topsort.shared.set(opaqueUserId: "user-1")
        Topsort.shared.reportedImpressionBids.clear()
        Topsort.shared.reportedRenderBids.clear()
    }

    override func tearDown() {
        Topsort.shared.isConfigured = true
        EventManager.shared._eventQueue = []
        #if canImport(Network)
            let mockNetwork = MockNetworkMonitor()
            mockNetwork.isConnected = true
            EventManager.shared.networkMonitor = mockNetwork
        #endif
        super.tearDown()
    }

    /// Everything tracked before this call, once the event manager has queued it. Pushes run in
    /// order on its serial queue, so a sentinel pushed last arrives after them.
    private func queued() -> [EventItem] {
        let sentinel = Event(entity: Entity(type: .product, id: "sentinel"), occurredAt: Date.now, id: "sentinel")
        EventManager.shared.push(event: .click(sentinel))
        let arrived = NSPredicate { _, _ in
            EventManager.shared._eventQueue?.contains { item in
                if case let .click(event) = item {
                    return event.id == "sentinel"
                }
                return false
            } ?? false
        }
        wait(for: [expectation(for: arrived, evaluatedWith: nil)], timeout: 3)
        return (EventManager.shared._eventQueue ?? []).filter { item in
            if case let .click(event) = item {
                return event.id != "sentinel"
            }
            return true
        }
    }

    private func count(_ kind: EventItemKind, in items: [EventItem]) -> Int {
        items.filter { $0.kind == kind }.count
    }

    private func impression(bid: String) -> Event {
        Event(resolvedBidId: bid, occurredAt: Date.now)
    }

    func testRepeatPromotedImpressionIsDropped() {
        Topsort.shared.track(impression: impression(bid: "bid-1"))
        Topsort.shared.track(impression: impression(bid: "bid-1"))
        Topsort.shared.track(impression: impression(bid: "bid-2"))
        XCTAssertEqual(count(.impression, in: queued()), 2)
    }

    func testRepeatRenderIsDropped() {
        Topsort.shared.track(render: RenderEvent(resolvedBidId: "bid-1", occurredAt: Date.now))
        Topsort.shared.track(render: RenderEvent(resolvedBidId: "bid-1", occurredAt: Date.now))
        XCTAssertEqual(count(.render, in: queued()), 1)
    }

    func testRenderDoesNotUseUpTheImpressionOfItsBid() {
        Topsort.shared.track(render: RenderEvent(resolvedBidId: "bid-1", occurredAt: Date.now))
        Topsort.shared.track(impression: impression(bid: "bid-1"))
        let items = queued()
        XCTAssertEqual(count(.render, in: items), 1)
        XCTAssertEqual(count(.impression, in: items), 1)
    }

    func testOrganicImpressionsAndClicksAreNeverDropped() {
        let organic = Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)
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

    func testANewUserIdForgetsReportedBids() {
        Topsort.shared.track(impression: impression(bid: "bid-1"))
        Topsort.shared.track(render: RenderEvent(resolvedBidId: "bid-1", occurredAt: Date.now))
        Topsort.shared.set(opaqueUserId: "user-2")
        Topsort.shared.track(impression: impression(bid: "bid-1"))
        Topsort.shared.track(render: RenderEvent(resolvedBidId: "bid-1", occurredAt: Date.now))
        let items = queued()
        XCTAssertEqual(count(.impression, in: items), 2)
        XCTAssertEqual(count(.render, in: items), 2)
    }

    func testSettingTheSameUserIdKeepsReportedBids() {
        Topsort.shared.track(impression: impression(bid: "bid-1"))
        Topsort.shared.set(opaqueUserId: "user-1")
        Topsort.shared.track(impression: impression(bid: "bid-1"))
        XCTAssertEqual(count(.impression, in: queued()), 1)
    }

    func testReconfiguringWithTheSameIdentityKeepsReportedBids() throws {
        Topsort.shared.track(impression: impression(bid: "bid-1"))
        try Topsort.shared.configure(Configuration(apiKey: "refreshed-key"))
        Topsort.shared.track(impression: impression(bid: "bid-1"))
        XCTAssertEqual(count(.impression, in: queued()), 1)
    }

    func testSwitchingIdentityModeForgetsReportedBids() throws {
        Topsort.shared.track(impression: impression(bid: "bid-1"))
        var config = Configuration(apiKey: "test-key")
        config.identity = .ephemeral
        try Topsort.shared.configure(config)
        EventManager.shared.flushAt = 10000
        Topsort.shared.track(impression: impression(bid: "bid-1"))
        XCTAssertEqual(count(.impression, in: queued()), 2)
    }
}
