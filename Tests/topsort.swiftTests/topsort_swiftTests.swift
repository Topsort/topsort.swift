@testable import Topsort
import XCTest

final class topsort_swiftTests: XCTestCase {
    func testExample() throws {
        // XCTest Documentation
        // https://developer.apple.com/documentation/xctest

        // Defining Test Cases and Test Methods
        // https://developer.apple.com/documentation/xctest/defining_test_cases_and_test_methods
    }

    func testEncodeModels() throws {
        let date = Date()
        let iso8601DateFormatter = ISO8601DateFormatter()
        iso8601DateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let occurredAt = iso8601DateFormatter.string(from: date)

        Topsort.shared.set(opaqueUserId: "user-id")

        let myEvent = Event(entity: Entity(type: EntityType.product, id: "product-id"), occurredAt: date)

        let jsonData = try! JSONEncoder().encode(myEvent)
        let decoded = try! JSONSerialization.jsonObject(with: jsonData, options: []) as! [String: Any]

        XCTAssertEqual(decoded["opaqueUserId"] as! String, "user-id")
        XCTAssertEqual((decoded["entity"] as! [String: Any])["type"] as! String, "product")
        XCTAssertEqual(decoded["occurredAt"] as! String, occurredAt)
    }

    func testPeriodicEvent() throws {
        let q = DispatchQueue(label: "test")
        var cnt = 0
        var completed = false
        let pe = PeriodicEvent(interval: 1, action: { cnt += 1 }, queue: q)
        pe.start()
        let semaphore = DispatchSemaphore(value: 0)
        q.asyncAfter(deadline: .now() + 3.5) {
            pe.stop()
            q.asyncAfter(deadline: .now() + 2) {
                completed = true
                semaphore.signal()
            }
        }
        semaphore.wait()
        XCTAssert(completed)
        XCTAssertEqual(cnt, 3)
    }

    func testFilePersistedValue() {
        let path = PathHelper.path(for: "test.plist")
        var fpv = FilePersistedValue<Int>(storePath: path)
        fpv.wrappedValue = 1
        XCTAssertEqual(fpv.wrappedValue, 1)
        fpv.wrappedValue = 2
        sleep(1)
        fpv = FilePersistedValue<Int>(storePath: path)
        XCTAssertEqual(fpv.wrappedValue, 2)
        fpv.wrappedValue = 3
        sleep(1)
        fpv = FilePersistedValue<Int>(storePath: path)
        XCTAssertEqual(fpv.wrappedValue, 3)
        fpv.wrappedValue = nil
        sleep(1)
        fpv = FilePersistedValue<Int>(storePath: path)
        XCTAssertEqual(fpv.wrappedValue, nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }
}
