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

    private struct Key: Hashable {
        let opaqueUserId: String
        let resolvedBidId: String
    }

    /// A reported bid's place in the recency order. The list runs from `oldest` to `newest`,
    /// strong toward the newest end and weak back, so it holds no retain cycle.
    private final class Node {
        let key: Key
        var newer: Node?
        weak var older: Node?

        init(_ key: Key) {
            self.key = key
        }
    }

    private let capacity: Int
    private let lock = NSLock()
    // A dictionary for the lookup and a linked list for the order: every operation is O(1),
    // as with topsort.kt's access-ordered LinkedHashMap. Guarded by `lock`.
    private var nodes: [Key: Node] = [:]
    private var oldest: Node?
    private var newest: Node?
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
            if let node = nodes[key] {
                unlink(node)
                append(node)
                return false
            }
            let node = Node(key)
            nodes[key] = node
            append(node)
            if nodes.count > capacity, let evicted = oldest {
                unlink(evicted)
                nodes[evicted.key] = nil
            }
            return true
        }
    }

    /// Forgets the report of `resolvedBidId` for `opaqueUserId`, so the next one is sent. Called
    /// when the event queue gives up on the event: the API never accepted the first report.
    func unmark(_ resolvedBidId: String, for opaqueUserId: String) {
        let key = Key(opaqueUserId: opaqueUserId, resolvedBidId: resolvedBidId)
        lock.withLock {
            guard let node = nodes.removeValue(forKey: key) else { return }
            unlink(node)
        }
    }

    /// Must hold `lock`.
    private func unlink(_ node: Node) {
        if let older = node.older {
            older.newer = node.newer
        } else {
            oldest = node.newer
        }
        if let newer = node.newer {
            newer.older = node.older
        } else {
            newest = node.older
        }
        node.older = nil
        node.newer = nil
    }

    /// Must hold `lock`.
    private func append(_ node: Node) {
        node.older = newest
        newest?.newer = node
        newest = node
        if oldest == nil {
            oldest = node
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
            nodes.removeAll()
            oldest = nil
            newest = nil
            repeatDropped = false
        }
    }
}
