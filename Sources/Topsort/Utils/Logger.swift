import Foundation

enum Logger {
    static var logLevel: LogLevel = .error

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
