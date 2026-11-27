@testable import Topsort
import XCTest

/// Pins what the SDK writes to disk and its batch limits. Changing any value here is a
/// persisted-format change: it needs a migration and an explicit edit of this test.
final class PersistedFormatTests: XCTestCase {
    func testLimits() {
        XCTAssertEqual(MAX_IN_PROGRESS, 10)
        XCTAssertEqual(MAX_RETRIES, 50)
        XCTAssertEqual(MAX_QUEUED_EVENTS, 5000)
        XCTAssertEqual(MAX_EVENTS_PER_BATCH, 500)
        XCTAssertEqual(MAX_EVENTS_PER_TYPE_PER_BATCH, 50)
    }

    func testRetryBackoffIsCappedExponential() {
        let last = Date(timeIntervalSince1970: 1_700_000_000)
        func wait(_ retries: Int) -> TimeInterval {
            PendingEvents(id: UUID(), data: Data(), createdAt: last, retries: retries, lastRetry: last).retryAfter.timeIntervalSince(last)
        }
        XCTAssertEqual(wait(0), 10)
        XCTAssertEqual(wait(3), 80)
        XCTAssertEqual(wait(50), 1200)
    }

    private let clickJSON = #"{"click":{"_0":{"id":"e1","occurredAt":"2026-03-18T12:00:00.000Z","opaqueUserId":"u1","resolvedBidId":"bid1"}}}"#

    func testEventItemEncodedShape() throws {
        let event = Event(resolvedBidId: "bid1", occurredAt: Date(timeIntervalSince1970: 1_773_835_200), opaqueUserId: "u1", id: "e1")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = try String(decoding: encoder.encode(EventItem.click(event)), as: UTF8.self)
        XCTAssertEqual(json, clickJSON)
    }

    func testEventItemDecodesStoredShape() throws {
        guard case let .click(event) = try JSONDecoder().decode(EventItem.self, from: Data(clickJSON.utf8)) else {
            return XCTFail("expected a click")
        }
        XCTAssertEqual(event.id, "e1")
        XCTAssertEqual(event.resolvedBidId, "bid1")
    }

    func testPendingEventsEncodedShape() throws {
        let id = try XCTUnwrap(UUID(uuidString: "6B0E8E57-1D14-4E7A-9C2B-3A2C1D5E6F70"))
        let record = PendingEvents(id: id, data: Data("{}".utf8), createdAt: Date(timeIntervalSince1970: 1_700_000_000), retries: 3, lastRetry: Date(timeIntervalSince1970: 1_700_000_100))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = try String(decoding: encoder.encode(record), as: UTF8.self)
        XCTAssertEqual(json, #"{"createdAt":721692800,"data":"e30=","id":"6B0E8E57-1D14-4E7A-9C2B-3A2C1D5E6F70","lastRetry":721692900,"retries":3}"#)
    }

    // The 1.0.0 on-disk plist fixture for PendingEvents is pinned in
    // filePersistedValue_deferTests.swift (testPendingRecordWrittenBy1_0_0StillLoads).
}
