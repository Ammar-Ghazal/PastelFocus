import Foundation

/// How the Today list is ordered (Settings → General).
public enum TaskSort: String, CaseIterable, Sendable {
    case priority, title, tag

    public var label: String {
        switch self {
        case .priority: return "Priority"
        case .title: return "Task name (A–Z)"
        case .tag: return "Tag (A–Z)"
        }
    }

    /// Open tasks first, then tasks moved to #later, then finished ones; each group in this order.
    /// Ties keep the order the tasks have in the notes.
    public func sorted(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.enumerated().sorted { a, b in
            let (x, y) = (a.element, b.element)
            if Self.group(x) != Self.group(y) { return Self.group(x) < Self.group(y) }
            switch self {
            case .priority:
                break
            case .title:
                let c = x.title.localizedStandardCompare(y.title)
                if c != .orderedSame { return c == .orderedAscending }
            case .tag:
                // Tasks without a tag go last.
                switch (x.category, y.category) {
                case let (p?, q?) where p != q: return p.localizedStandardCompare(q) == .orderedAscending
                case (_?, nil): return true
                case (nil, _?): return false
                default: break
                }
            }
            if x.priority.sortRank != y.priority.sortRank { return x.priority.sortRank < y.priority.sortRank }
            return a.offset < b.offset
        }.map(\.element)
    }

    static func group(_ t: TaskItem) -> Int {
        t.status.isOpen ? (t.isLater ? 1 : 0) : 2
    }
}
