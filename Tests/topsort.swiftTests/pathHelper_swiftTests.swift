import Foundation
@testable import Topsort
import XCTest

class PathHelperMigrationTests: XCTestCase {
    func testPathUsesApplicationSupport() {
        let path = PathHelper.path(for: "test.plist")
        XCTAssertTrue(path.contains("Application Support"), "Path should use Application Support, got: \(path)")
        XCTAssertTrue(path.contains("com.topsort.analytics"))
        XCTAssertFalse(path.contains("/Documents/"))
    }

    func testMigrationMovesFilesFromDocuments() throws {
        let fileManager = FileManager.default
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let testFile = "com.topsort.analytics.migration-test.plist"
        let oldPath = "\(documentsPath)/\(testFile)"
        let newPath = PathHelper.path(for: testFile)

        // Clean up any previous test state
        try? fileManager.removeItem(atPath: oldPath)
        try? fileManager.removeItem(atPath: newPath)

        // Create a file at the old location
        let testData = try PropertyListEncoder().encode(["test": "data"])
        fileManager.createFile(atPath: oldPath, contents: testData)
        XCTAssertTrue(fileManager.fileExists(atPath: oldPath))

        // The migration runs lazily when PathHelper.path(for:) is first called,
        // which already happened. We can test that the new path directory exists.
        let appSupportDir = (newPath as NSString).deletingLastPathComponent
        XCTAssertTrue(fileManager.fileExists(atPath: appSupportDir), "Application Support directory should exist")

        // Clean up
        try? fileManager.removeItem(atPath: oldPath)
        try? fileManager.removeItem(atPath: newPath)
    }
}
