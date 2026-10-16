import Foundation

/// The resolved bids this process has already reported, for one event type.
///
/// A resolved bid identifies one ad placed in one slot, so it earns one render and one
/// impression. The SDK cannot see why a caller reports the same bid again (a view that reappears
/// while scrolling a lazy list, a banner rebuilt by its parent) and does not need to: the repeat
/// is wrong whatever produced it, and on a CPM campaign the impression is billed. Every event gets
/// a fresh `id`, so the API's own deduplication never sees these as repeats.
///
/// Renders and impressions each get their own instance: the render fires when the ad enters the
/// view and the impression once it is visible, and the first must not use up the second.
///
/// In memory and bounded, as in topsort.kt: a relaunch that reports a bid once more is not the
/// failure this guards against, and past `capacity` the least recently reported bid is forgotten.
/// The cap is far above the distinct bids a real session sees.
final class ReportedBids {
    static let defaultCapacity = 512

    private let capacity: Int
    private let lock = NSLock()
    /// Least recently reported first. A linear scan is cheap at this size.
    private var bids: [String] = []

    init(capacity: Int = ReportedBids.defaultCapacity) {
        self.capacity = capacity
    }

    /// Records `resolvedBidId` and returns whether this is its first report. A repeat makes it the
    /// most recently reported again, so a bid that keeps reappearing is never the one evicted.
    func markReported(_ resolvedBidId: String) -> Bool {
        lock.withLock {
            if let index = bids.firstIndex(of: resolvedBidId) {
                bids.remove(at: index)
                bids.append(resolvedBidId)
                return false
            }
            bids.append(resolvedBidId)
            if bids.count > capacity {
                bids.removeFirst()
            }
            return true
        }
    }

    func clear() {
        lock.withLock { bids.removeAll() }
    }
}
