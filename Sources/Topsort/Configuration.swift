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

/// What happens to the user id the SDK mints when the host has not supplied one.
public enum Identity: Sendable {
    /// The minted id is written to disk and reused across launches, so the device keeps one
    /// identity (the default). A persistent device-scoped pseudonymous id is personal data
    /// under most privacy regimes.
    case persisted
    /// The minted id lives only for this process: the id itself is never written, and any id
    /// stored by an earlier launch is removed on `configure` (the file deletion is asynchronous).
    /// Queued events that carry the id are still persisted until they are sent. Call
    /// `set(opaqueUserId:)` after `configure`, not before — entering this mode clears it. For a
    /// signed-out user or withdrawn consent; events are delivered and billed, they will not
    /// audience-match.
    case ephemeral
}

public struct Configuration {
    public let apiKey: String
    public var url: String?
    public var auctionsTimeout: TimeInterval?
    public var flushAt: Int = 30
    public var flushInterval: TimeInterval = 30
    public var logLevel: LogLevel = .warning
    public var identity: Identity = .persisted
    /// Called when the SDK discards events it will never deliver, with the reason and how many.
    /// Every discard is data the marketplace will not see, so a host that wants to know about
    /// loss — a metric, a breadcrumb — sets this. Runs on the SDK's serial queue, ahead of the
    /// work it was doing: keep it quick, capture nothing that must not outlive the process, and
    /// do not call `configure` from it (`track` and `flush` are fine).
    public var onEventsDiscarded: (@Sendable (DiscardReason, Int) -> Void)?
    /// Called when the API acknowledges a batch, with how many events it carried.
    ///
    /// Delivery is otherwise unreported: nothing else in the SDK marks a batch as landed, and an
    /// in-app network inspector may not show the response for the session events are sent on, in
    /// which case a request that was accepted looks indistinguishable from one still in flight.
    /// Set this to confirm delivery — a QA check, a counter to reconcile against the dashboard.
    ///
    /// Runs on the SDK's serial queue, ahead of the work it was doing, under the same rules as
    /// `onEventsDiscarded`: keep it quick, capture nothing that must not outlive the process,
    /// and do not call `configure` from it (`track` and `flush` are fine).
    ///
    /// Acknowledged means the API accepted the batch, not that every event in it was valid, and
    /// the count is of events sent rather than events newly recorded — a redelivery after a lost
    /// acknowledgement is counted again, though the API dedups it on each event's `id`.
    public var onEventsDelivered: (@Sendable (Int) -> Void)?

    public init(apiKey: String) {
        self.apiKey = apiKey
    }
}
