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
}
