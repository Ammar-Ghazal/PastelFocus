import Foundation

/// Checkbox state, using the Obsidian Tasks plugin's status characters.
public enum TaskStatus: String, Codable, Sendable, CaseIterable {
    case todo = " "
    case inProgress = "/"
    case done = "x"
    case cancelled = "-"

    public init(marker: Character) {
        switch marker {
        case "x", "X": self = .done
        case "/": self = .inProgress
        case "-": self = .cancelled
        default: self = .todo
        }
    }

    public var isOpen: Bool { self == .todo || self == .inProgress }
}

public enum Priority: Int, Codable, Sendable, Comparable, CaseIterable {
    case none = 0, low = 1, medium = 2, high = 3

    public static func < (a: Priority, b: Priority) -> Bool { a.rawValue < b.rawValue }

    /// Tasks plugin emoji. `none` has no marker.
    public var emoji: String? {
        switch self {
        case .high: return "⏫"
        case .medium: return "🔼"
        case .low: return "🔽"
        case .none: return nil
        }
    }

    public var label: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        case .none: return ""
        }
    }
}

/// One task line from the vault, plus where it lives.
public struct TaskItem: Equatable, Codable, Sendable, Identifiable {
    /// 🆔 value. Nil only for lines the app has not stamped yet.
    public var taskID: String?
    public var status: TaskStatus
    /// Free text with all recognised fields removed (tags kept).
    public var description: String
    public var priority: Priority
    /// True when the priority came from a legacy `**P1 · 90 min**` marker.
    public var priorityFromLegacy: Bool
    public var estimateSessions: Int?
    public var actualSessions: Int?
    public var created: String?
    public var scheduled: String?
    public var due: String?
    public var start: String?
    public var completed: String?
    public var notes: [String]

    /// Vault-relative path of the file holding the line.
    public var file: String
    public var lineIndex: Int
    public var indent: String

    public var id: String { taskID ?? "\(file)#\(lineIndex)" }

    public init(taskID: String? = nil, status: TaskStatus = .todo, description: String,
                priority: Priority = .none, priorityFromLegacy: Bool = false,
                estimateSessions: Int? = nil, actualSessions: Int? = nil,
                created: String? = nil, scheduled: String? = nil, due: String? = nil,
                start: String? = nil, completed: String? = nil, notes: [String] = [],
                file: String = "", lineIndex: Int = 0, indent: String = "") {
        self.taskID = taskID
        self.status = status
        self.description = description
        self.priority = priority
        self.priorityFromLegacy = priorityFromLegacy
        self.estimateSessions = estimateSessions
        self.actualSessions = actualSessions
        self.created = created
        self.scheduled = scheduled
        self.due = due
        self.start = start
        self.completed = completed
        self.notes = notes
        self.file = file
        self.lineIndex = lineIndex
        self.indent = indent
    }

    // MARK: Display helpers

    public var tags: [String] { TaskLineParser.tags(in: description) }

    /// The first tag on the line (lowercased), skipping `#later`, which marks priority. It decides
    /// the plant a session grows and is the category used in analytics.
    public var category: String? {
        tags.map { $0.lowercased() }.first { !TagRegistry.reserved.contains($0) }
    }

    public var isLater: Bool { tags.contains { $0.lowercased() == "later" } }

    /// Description without tags or the legacy marker, split into title and subtitle at " — ".
    public var title: String { displayParts.title }
    public var subtitle: String? { displayParts.subtitle }

    private var displayParts: (title: String, subtitle: String?) {
        var text = TaskLineParser.stripLegacyMarker(description)
        text = TaskLineParser.removingTags(text)
        let parts = text.components(separatedBy: " — ")
        let title = parts[0].trimmingCharacters(in: .whitespaces)
        let rest = parts.dropFirst().joined(separator: " — ").trimmingCharacters(in: .whitespaces)
        return (title, rest.isEmpty ? nil : rest)
    }
}

