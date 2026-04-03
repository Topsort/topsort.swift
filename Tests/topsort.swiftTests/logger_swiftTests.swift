@testable import Topsort
import XCTest

class LoggerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Logger.logLevel = .warning
    }

    func testLogLevelComparable() {
        XCTAssertTrue(LogLevel.none < LogLevel.error)
        XCTAssertTrue(LogLevel.error < LogLevel.warning)
        XCTAssertTrue(LogLevel.warning < LogLevel.debug)
    }

    func testAutoclosureNotEvaluatedWhenSuppressed() {
        Logger.logLevel = .none
        var evaluated = false
        Logger.error({ evaluated = true; return "test" }())
        XCTAssertFalse(evaluated, "Autoclosure should not be evaluated when logLevel is .none")
    }

    func testAutoclosureEvaluatedWhenEnabled() {
        Logger.logLevel = .debug
        var evaluated = false
        Logger.debug({ evaluated = true; return "test" }())
        XCTAssertTrue(evaluated, "Autoclosure should be evaluated when logLevel allows it")
    }

    func testWarningVisibleAtDefaultLevel() {
        // Default is .warning — warnings should not be suppressed
        Logger.logLevel = .warning
        var evaluated = false
        Logger.warning({ evaluated = true; return "test" }())
        XCTAssertTrue(evaluated)
    }

    func testDebugSuppressedAtWarningLevel() {
        Logger.logLevel = .warning
        var evaluated = false
        Logger.debug({ evaluated = true; return "test" }())
        XCTAssertFalse(evaluated)
    }

    func testErrorVisibleAtAllLevelsExceptNone() {
        for level in [LogLevel.error, .warning, .debug] {
            Logger.logLevel = level
            var evaluated = false
            Logger.error({ evaluated = true; return "test" }())
            XCTAssertTrue(evaluated, "Error should be visible at logLevel \(level)")
        }

        Logger.logLevel = .none
        var evaluated = false
        Logger.error({ evaluated = true; return "test" }())
        XCTAssertFalse(evaluated, "Error should be suppressed at logLevel .none")
    }
}
