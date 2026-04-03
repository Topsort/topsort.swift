import Foundation
@testable import Topsort
import XCTest

class AuctionProductsTests: XCTestCase {
    func testInitWithValidIdsOnly() throws {
        let products = try AuctionProducts(ids: ["p1", "p2", "p3"])
        XCTAssertEqual(products.ids, ["p1", "p2", "p3"])
        XCTAssertNil(products.qualityScores)
    }

    func testInitWithMatchingQualityScores() throws {
        let products = try AuctionProducts(ids: ["p1", "p2"], qualityScores: [0.8, 0.9])
        XCTAssertEqual(products.ids, ["p1", "p2"])
        XCTAssertEqual(products.qualityScores, [0.8, 0.9])
    }

    func testInitThrowsOnMismatchedCounts() {
        XCTAssertThrowsError(try AuctionProducts(ids: ["p1", "p2"], qualityScores: [0.8])) { error in
            guard let validationError = error as? ValidationError else {
                XCTFail("Expected ValidationError, got \(error)")
                return
            }
            if case let .qualityScoreCountMismatch(idsCount, scoresCount) = validationError {
                XCTAssertEqual(idsCount, 2)
                XCTAssertEqual(scoresCount, 1)
            } else {
                XCTFail("Expected .qualityScoreCountMismatch case")
            }
        }
    }

    func testInitWithEmptyArrays() throws {
        let products = try AuctionProducts(ids: [], qualityScores: [])
        XCTAssertTrue(products.ids.isEmpty)
        XCTAssertEqual(products.qualityScores, [])
    }

    func testEquatable() throws {
        let a = try AuctionProducts(ids: ["p1"], qualityScores: [0.5])
        let b = try AuctionProducts(ids: ["p1"], qualityScores: [0.5])
        XCTAssertEqual(a, b)
    }

    func testCodableRoundTrip() throws {
        let original = try AuctionProducts(ids: ["p1", "p2"], qualityScores: [0.8, 0.9])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AuctionProducts.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
