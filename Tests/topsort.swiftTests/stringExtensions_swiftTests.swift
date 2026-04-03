#if canImport(CommonCrypto)
    @testable import Topsort
    import XCTest

    class StringExtensionsTests: XCTestCase {
        func testHexSha1HashKnownValue() {
            // SHA1("hello") = aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d
            XCTAssertEqual("hello".hexSha1HashString(), "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d")
        }

        func testHexSha1HashEmptyString() {
            // SHA1("") = da39a3ee5e6b4b0d3255bfef95601890afd80709
            XCTAssertEqual("".hexSha1HashString(), "da39a3ee5e6b4b0d3255bfef95601890afd80709")
        }

        func testHexSha1HashProducesLowercaseHex() {
            let hash = "test".hexSha1HashString()
            XCTAssertEqual(hash, hash.lowercased())
            XCTAssertEqual(hash.count, 40) // SHA1 = 20 bytes = 40 hex chars
        }
    }
#endif
