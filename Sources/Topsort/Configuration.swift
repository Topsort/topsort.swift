import Foundation

public enum LogLevel: Int, Comparable {
    case none = 0
    case error = 1
    case warning = 2
    case debug = 3

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct Configuration {
    public let apiKey: String
    public var url: String?
    public var auctionsTimeout: TimeInterval?
    public var flushAt: Int = 30
    public var flushInterval: TimeInterval = 30
    public var logLevel: LogLevel = .warning

    public init(apiKey: String) {
        self.apiKey = apiKey
    }
}
