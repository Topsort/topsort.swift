import Foundation

/// The resolved bids this process has already reported, per user, for one event type.
///
/// A resolved bid identifies one ad placed in one slot, so it earns one render and one
/// impression. The SDK cannot see why a caller reports the same bid again (a view that reappears
/// while scrolling a lazy list, a banner rebuilt by its parent) and does not need to: the repeat
/// is wrong whatever produced it, and on a CPM campaign the impression is billed. Every event gets
/// a fresh `id`, so the API's own deduplication never sees these as repeats.
///
/// Keyed on the event's own `opaqueUserId` as well as the bid, because events carry their user:
/// a host that passes ids per event (a shared device, a kiosk) never changes `Topsort.shared`'s
/// id, and another user's report of the same bid is that user's own, not a repeat.
///
/// Renders and impressions each get their own instance: the render fires when the ad enters the
/// view and the impression once it is visible, and the first must not use up the second.
///
/// In memory and bounded, as in topsort.kt: a relaunch that reports a bid once more is not the
/// failure this guards against, and past `capacity` the least recently reported bid is forgotten.
/// The cap is far above the distinct bids a real session sees.
final class ReportedBids {
    static let defaultCapacity = 512

    private struct Key: Equatable {
        let opaqueUserId: String
        let resolvedBidId: String
    }

    private let capacity: Int
    private let lock = NSLock()
    /// Least recently reported first. A linear scan is cheap at this size.
    private var reported: [Key] = []
    private var repeatDropped = false

    init(capacity: Int = ReportedBids.defaultCapacity) {
        self.capacity = capacity
    }

    /// Records `resolvedBidId` for `opaqueUserId` and returns whether this is its first report. A
    /// repeat makes it the most recently reported again, so a bid that keeps reappearing is never
    /// the one evicted.
    func markReported(_ resolvedBidId: String, for opaqueUserId: String) -> Bool {
        let key = Key(opaqueUserId: opaqueUserId, resolvedBidId: resolvedBidId)
        return lock.withLock {
            if let index = reported.firstIndex(of: key) {
                reported.remove(at: index)
                reported.append(key)
                return false
            }
            reported.append(key)
            if reported.count > capacity {
                reported.removeFirst()
            }
            return true
        }
    }

    /// Whether this is the first repeat dropped in this process. The caller warns once and logs
    /// the rest at debug: a lazy list reporting from `onAppear` repeats on every scroll, and a
    /// warning each time would bury every other warning.
    func isFirstRepeat() -> Bool {
        lock.withLock {
            defer { repeatDropped = true }
            return !repeatDropped
        }
    }

    /// Only tests call this, to start each one without the bids earlier tests reported.
    func clear() {
        lock.withLock {
            reported.removeAll()
            repeatDropped = false
        }
    }
}
