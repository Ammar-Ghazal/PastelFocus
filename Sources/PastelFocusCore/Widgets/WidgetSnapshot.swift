import Foundation

/// What the WidgetKit extension shows. The app writes it into the shared App Group container;
/// the sandboxed widget never touches the vault.
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public struct Row: Codable, Sendable, Equatable {
        public var id: String
        public var title: String
        public var tag: String?
        public var done: Bool
        public var high: Bool
        public init(id: String, title: String, tag: String?, done: Bool, high: Bool) {
            self.id = id; self.title = title; self.tag = tag; self.done = done; self.high = high
        }
    }

    public var updated: Date
    public var tasks: [Row]
    public var doneCount: Int
    public var totalCount: Int
    public var phase: FocusPhase
    public var timerTitle: String
    /// Set while running: lets the widget count down by itself with `Text(timerInterval:)`.
    public var timerEnd: Date?
    public var remainingS: Int
    public var nextTask: Row?
    public var focusedMinutesToday: Int
    public var goodDays: Int
    /// Stopwatch only: when counting started (adjusted for pauses), so the widget can count up itself.
    public var timerStart: Date? = nil
    /// Stopwatch only: seconds so far (shown while paused).
    public var elapsedS: Int? = nil
    /// Theme and colour combo the app is showing, so widgets match it.
    public var theme: ThemeSelection? = nil

    public init(updated: Date, tasks: [Row], doneCount: Int, totalCount: Int, phase: FocusPhase, timerTitle: String,
                timerEnd: Date?, remainingS: Int, nextTask: Row?, focusedMinutesToday: Int, goodDays: Int) {
        self.updated = updated; self.tasks = tasks; self.doneCount = doneCount; self.totalCount = totalCount
        self.phase = phase; self.timerTitle = timerTitle; self.timerEnd = timerEnd; self.remainingS = remainingS
        self.nextTask = nextTask; self.focusedMinutesToday = focusedMinutesToday; self.goodDays = goodDays
    }

    public static let empty = WidgetSnapshot(updated: .distantPast, tasks: [], doneCount: 0, totalCount: 0, phase: .idle,
                                             timerTitle: "Pick a task", timerEnd: nil, remainingS: 25 * 60, nextTask: nil,
                                             focusedMinutesToday: 0, goodDays: 0)

    public var progress: Double { totalCount == 0 ? 0 : Double(doneCount) / Double(totalCount) }
}

/// A tap in a widget, queued for the app to apply (widgets can't edit the vault themselves).
public struct WidgetCommand: Codable, Sendable, Equatable {
    public enum Action: String, Codable, Sendable { case toggleTask, startFocus, pauseFocus, resumeFocus }
    public var action: Action
    public var taskID: String?
    public var at: Date
    public init(action: Action, taskID: String?, at: Date) { self.action = action; self.taskID = taskID; self.at = at }
}

/// Shared App Group paths and read/write helpers used by both the app and the widget extension.
public enum WidgetBridge {
    public static let appGroup = "58FZ49BXRF.com.ammarghazal.pastelfocus"

    public static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    public static func snapshotURL(in dir: URL) -> URL { dir.appendingPathComponent("snapshot.json") }
    public static func commandsURL(in dir: URL) -> URL { dir.appendingPathComponent("widget-commands.jsonl") }

    public static func write(_ s: WidgetSnapshot, to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        try e.encode(s).write(to: snapshotURL(in: dir), options: .atomic)
    }

    public static func read(from dir: URL) -> WidgetSnapshot {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: snapshotURL(in: dir)), let s = try? d.decode(WidgetSnapshot.self, from: data) else { return .empty }
        return s
    }

    public static func enqueue(_ c: WidgetCommand, in dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let line = try e.encode(c) + Data("\n".utf8)
        let url = commandsURL(in: dir)
        if let h = try? FileHandle(forWritingTo: url) { defer { try? h.close() }; try h.seekToEnd(); try h.write(contentsOf: line) }
        else { try line.write(to: url) }
    }

    /// Reads and clears pending commands.
    public static func drain(in dir: URL) -> [WidgetCommand] {
        let url = commandsURL(in: dir)
        guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else { return [] }
        try? "".write(to: url, atomically: true, encoding: .utf8)
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").compactMap { try? d.decode(WidgetCommand.self, from: Data($0.utf8)) }
    }
}
