import Foundation

enum Logger {
    private static let lock = NSLock()
    private static var _logLevel: LogLevel = .error
    static var logLevel: LogLevel {
        get { lock.withLock { _logLevel } }
        set { lock.withLock { _logLevel = newValue } }
    }

    static func error(_ message: @autoclosure () -> String) {
        guard logLevel >= .error else { return }
        print("[Topsort] [ERROR] \(message())")
    }

    static func warning(_ message: @autoclosure () -> String) {
        guard logLevel >= .warning else { return }
        print("[Topsort] [WARN] \(message())")
    }

    static func debug(_ message: @autoclosure () -> String) {
        guard logLevel >= .debug else { return }
        print("[Topsort] [DEBUG] \(message())")
    }
}
