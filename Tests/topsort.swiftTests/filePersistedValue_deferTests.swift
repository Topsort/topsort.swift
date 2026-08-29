@testable import Topsort
import XCTest

class FilePersistedValueDeferTests: XCTestCase {
    var path: String!

    override func setUp() {
        super.setUp()
        path = PathHelper.path(for: "test-defer-\(UUID().uuidString).plist")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: path)
        super.tearDown()
    }

    func testDeferredWriteDoesNotPersistImmediately() {
        let fpv = FilePersistedValue<Int>(storePath: path)
        fpv.deferPersistence = true
        fpv.wrappedValue = 42

        // In-memory value is updated
        XCTAssertEqual(fpv.wrappedValue, 42)

        // But disk should NOT have the value yet (debounce is 5s)
        let reloaded = FilePersistedValue<Int>(storePath: path)
        XCTAssertNil(reloaded.wrappedValue, "Deferred write should not persist immediately")
    }

    func testPersistIfDirtyForcesWrite() {
        let fpv = FilePersistedValue<Int>(storePath: path)
        fpv.deferPersistence = true
        fpv.wrappedValue = 99

        // Force persist
        fpv.persistIfDirty()

        // Now disk should have the value
        let reloaded = FilePersistedValue<Int>(storePath: path)
        XCTAssertEqual(reloaded.wrappedValue, 99)
    }

    func testPersistIfDirtyNoopWhenClean() {
        let fpv = FilePersistedValue<Int>(storePath: path)
        fpv.deferPersistence = true

        // Write and force persist
        fpv.wrappedValue = 1
        fpv.persistIfDirty()

        // Update in memory only
        fpv.wrappedValue = 2

        // Force persist again — should write 2
        fpv.persistIfDirty()

        let reloaded = FilePersistedValue<Int>(storePath: path)
        XCTAssertEqual(reloaded.wrappedValue, 2)
    }

    func testNonDeferredModeStillPersistsImmediately() {
        let fpv = FilePersistedValue<Int>(storePath: path)
        fpv.deferPersistence = false
        fpv.wrappedValue = 55

        // Wait for async persist
        sleep(1)

        let reloaded = FilePersistedValue<Int>(storePath: path)
        XCTAssertEqual(reloaded.wrappedValue, 55)
    }

    func testDebouncedPersistEventuallyWrites() {
        let fpv = FilePersistedValue<Int>(storePath: path)
        fpv.deferPersistence = true
        fpv.debounceInterval = 1.0 // Short debounce for testing
        fpv.wrappedValue = 77

        // Wait for debounce to fire
        let exp = expectation(description: "debounce")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { exp.fulfill() }
        wait(for: [exp], timeout: 3)

        let reloaded = FilePersistedValue<Int>(storePath: path)
        XCTAssertEqual(reloaded.wrappedValue, 77)
    }

    // MARK: - Pending-set persistence

    /// What the pipeline writes on one launch must load unchanged on the next.
    func testPendingSetRoundTripsThroughDisk() throws {
        let id = UUID()
        let body = try JSONEncoder().encode(Events(impressions: [Event(entity: Entity(type: .product, id: "p1"), occurredAt: Date.now)]))
        let record = PendingEvents(id: id, data: body, createdAt: Date(timeIntervalSince1970: 1_700_000_000), retries: 3, lastRetry: Date(timeIntervalSince1970: 1_700_000_100))
        FilePersistedValue<[UUID: PendingEvents]>(storePath: path).wrappedValue = [id: record]
        wait(for: [expectation(for: NSPredicate { _, _ in FileManager.default.fileExists(atPath: self.path) }, evaluatedWith: nil)], timeout: 2)

        let loaded = try XCTUnwrap(FilePersistedValue<[UUID: PendingEvents]>(storePath: path).wrappedValue?[id])
        XCTAssertEqual(loaded.id, id)
        XCTAssertEqual(loaded.data, body)
        XCTAssertEqual(loaded.createdAt, record.createdAt)
        XCTAssertEqual(loaded.retries, 3)
        XCTAssertEqual(loaded.lastRetry, record.lastRetry)
        XCTAssertEqual(loaded.eventCount, 1)
    }

    /// The on-disk shape has not changed since 1.0.0. Changing it means records written by an
    /// older version stop loading, so it needs a migration, not just a new field.
    func testPendingRecordSchemaIsUnchangedSince1_0_0() throws {
        let record = PendingEvents(id: UUID(), data: Data(), createdAt: Date(), retries: 0, lastRetry: Date())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["id", "data", "createdAt", "retries", "lastRetry"])
    }
}
