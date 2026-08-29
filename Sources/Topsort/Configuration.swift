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

/// Why queued events were thrown away without being delivered.
///
/// New reasons may be added in minor releases; keep a `default` branch when switching on this.
public enum DiscardReason: Sendable {
    /// Evicted to keep the queue under its capacity bound.
    case queueOverCapacity
    /// The API rejected the batch with a 4xx; retrying the same body would be rejected again.
    case permanentlyRejected
    /// The batch failed on every one of its retries.
    case retriesExhausted
    /// The event cannot be serialized, so nothing can ever send it.
    case unserializable
}

public struct Configuration {
    public let apiKey: String
    public var url: String?
    public var auctionsTimeout: TimeInterval?
    public var flushAt: Int = 30
    public var flushInterval: TimeInterval = 30
    public var logLevel: LogLevel = .warning
    /// Called when the SDK discards events it will never deliver, with the reason and how many.
    /// Every discard is data the marketplace will not see, so a host that wants to know about
    /// loss — a metric, a breadcrumb — sets this. Runs on the SDK's serial queue, ahead of the
    /// work it was doing: keep it quick, capture nothing that must not outlive the process, and
    /// do not call `configure` from it (`track` and `flush` are fine).
    public var onEventsDiscarded: (@Sendable (DiscardReason, Int) -> Void)?

    public init(apiKey: String) {
        self.apiKey = apiKey
    }
}
