import CoreGraphics

/// Where a dragged filter pill belongs among the others (Today panel).
public enum PillReorder {
    /// The dragged pill goes before the pill under `point` if the point is on that pill's leading
    /// half, after it if on the trailing half. Only the other pills count, and the answer doesn't
    /// depend on where the dragged pill currently sits, so it can't flicker between two places.
    /// Returns the dragged pill's index in the new order, or nil when the point is over no pill.
    public static func insertionIndex(of dragged: String, in order: [String], at point: CGPoint, frames: [String: CGRect]) -> Int? {
        for (i, t) in order.filter({ $0 != dragged }).enumerated() {
            // Taller than the pill, so the gap between wrapped rows still counts as that row.
            guard let f = frames[t]?.insetBy(dx: -4, dy: -6), f.contains(point) else { continue }
            return point.x < f.midX ? i : i + 1
        }
        return nil
    }

    /// `order` with `dragged` moved to `index`.
    public static func moving(_ dragged: String, to index: Int, in order: [String]) -> [String] {
        var next = order.filter { $0 != dragged }
        next.insert(dragged, at: min(max(0, index), next.count))
        return next
    }
}
