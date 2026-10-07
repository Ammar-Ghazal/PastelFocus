import Foundation

/// Reads every task in the daily notes and the Backlog, and edits single lines by 🆔.
/// Every change made through the store is recorded in the events log.
public final class TaskStore {
    public let config: VaultConfig
    public let calendar: DayCalendar
    public let clock: Clock
    public let events: JSONLLog<TaskEvent>

    public struct ScanResult {
        public var tasks: [TaskItem]
        public var problems: [String]
    }

    public init(config: VaultConfig, calendar: DayCalendar, clock: Clock) {
        self.config = config
        self.calendar = calendar
        self.clock = clock
        self.events = JSONLLog(directory: config.logsDir, prefix: "events", calendar: calendar)
    }

    public var today: String { calendar.day(clock.now()) }

    // MARK: Reading

    public func taskFiles() -> [URL] {
        let fm = FileManager.default
        var files: [URL] = []
        if let names = try? fm.contentsOfDirectory(atPath: config.dailyDir.path) {
            files += names.filter { $0.hasSuffix(".md") && !$0.hasPrefix(".") }.sorted().map { config.dailyDir.appendingPathComponent($0) }
        }
        if fm.fileExists(atPath: config.backlog.path) { files.append(config.backlog) }
        return files
    }

    public func scan() -> ScanResult {
        var tasks: [TaskItem] = []
        var problems: [String] = []
        var seen: [String: String] = [:]
        for url in taskFiles() {
            let rel = config.relativePath(url)
            let parsed = Self.parseFile(lines: SafeFile.readLines(url), relative: rel)
            for line in parsed.badLines { problems.append("- `\(rel)` line \(line.index + 1): \(line.reason) — `\(line.text)`") }
            for t in parsed.tasks {
                if let id = t.taskID {
                    if let other = seen[id] {
                        problems.append("- `\(rel)` line \(t.lineIndex + 1): duplicate 🆔 \(id) (also in `\(other)`)")
                        continue
                    }
                    seen[id] = rel
                }
                tasks.append(t)
            }
        }
        return ScanResult(tasks: tasks, problems: problems)
    }

    struct BadLine { let index: Int; let text: String; let reason: String }

    static let badDate = try! NSRegularExpression(pattern: #"(➕|⏳|📅|✅|🛫)(?!\s*\d{4}-\d{2}-\d{2})"#)

    static func parseFile(lines: [String], relative: String) -> (tasks: [TaskItem], badLines: [BadLine]) {
        var tasks: [TaskItem] = []
        var bad: [BadLine] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if var t = TaskLineParser.parse(line, file: relative, lineIndex: i) {
                let ns = line as NSString
                if badDate.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) != nil {
                    bad.append(BadLine(index: i, text: line.trimmingCharacters(in: .whitespaces), reason: "date field without a YYYY-MM-DD date"))
                }
                // Indented plain bullets directly under a task are its notes.
                var j = i + 1
                while j < lines.count {
                    let next = lines[j]
                    let indentLen = next.prefix { $0 == " " || $0 == "\t" }.count
                    guard indentLen > t.indent.count, !TaskLineParser.isTaskLine(next),
                          next.trimmingCharacters(in: .whitespaces).hasPrefix("- ") else { break }
                    t.notes.append(String(next.trimmingCharacters(in: .whitespaces).dropFirst(2)))
                    j += 1
                }
                if !t.description.isEmpty { tasks.append(t) }
                i = j
                continue
            }
            i += 1
        }
        return (tasks, bad)
    }

    /// The day a task is planned for: ⏳ if set, else the daily note it sits in, else nil (Backlog).
    public func effectiveDay(_ t: TaskItem) -> String? {
        t.scheduled ?? config.noteDay(forRelative: t.file)
    }

    /// Tasks for the Today panel: open tasks planned for today or earlier, plus tasks finished today.
    public func todayTasks(_ all: [TaskItem]) -> [TaskItem] {
        let day = today
        return all.filter { t in
            guard t.indent.isEmpty || t.taskID != nil else { return false }
            if t.status == .done { return t.completed == day || (t.completed == nil && effectiveDay(t) == day) }
            if t.status == .cancelled { return false }
            guard let d = effectiveDay(t) else { return false }
            return d <= day
        }
    }

    // MARK: Writing

    /// Gives every task without a 🆔 a fresh one. Returns how many lines were stamped.
    @discardableResult
    public func stampMissingIDs() throws -> Int {
        var used = Set(scan().tasks.compactMap(\.taskID))
        var count = 0
        for url in taskFiles() {
            let lines = SafeFile.readLines(url)
            guard lines.contains(where: { TaskLineParser.parse($0)?.taskID == nil && TaskLineParser.isTaskLine($0) }) else { continue }
            try SafeFile.edit(url) { lines in
                for (i, line) in lines.enumerated() {
                    guard var t = TaskLineParser.parse(line), t.taskID == nil, !t.description.isEmpty else { continue }
                    var id = TaskLineParser.newID()
                    while used.contains(id) { id = TaskLineParser.newID() }
                    used.insert(id)
                    t.taskID = id
                    lines[i] = TaskLineParser.serialize(t)
                    count += 1
                }
            }
        }
        return count
    }

    public func find(_ id: String) -> TaskItem? {
        scan().tasks.first { $0.taskID == id }
    }

    /// Edits the one line carrying `🆔 id` and logs the events the closure returns.
    @discardableResult
    public func mutate(_ id: String, actor: Actor, reason: String? = nil,
                       _ change: (inout TaskItem) -> [TaskEvent]) throws -> TaskItem {
        guard let found = find(id) else { throw SafeFileError.lineNotFound("task 🆔 \(id)") }
        let url = config.url(forRelative: found.file)
        var result = found
        var newEvents: [TaskEvent] = []
        try SafeFile.edit(url) { lines in
            guard let idx = lines.firstIndex(where: { TaskLineParser.parse($0)?.taskID == id }),
                  var t = TaskLineParser.parse(lines[idx], file: found.file, lineIndex: idx) else {
                throw SafeFileError.lineNotFound("task 🆔 \(id)")
            }
            newEvents = change(&t)
            lines[idx] = TaskLineParser.serialize(t)
            result = t
        }
        for var e in newEvents {
            e.actor = actor
            if e.reason == nil { e.reason = reason }
            try events.append(e, at: e.at)
        }
        return result
    }

    public func setStatus(_ id: String, _ status: TaskStatus, actor: Actor, reason: String? = nil) throws {
        let now = clock.now()
        let day = today
        try mutate(id, actor: actor, reason: reason) { t in
            guard t.status != status else { return [] }
            let old = t.status
            t.status = status
            t.completed = status == .done ? day : nil
            let type: TaskEventType = switch status {
            case .done: .completed
            case .cancelled: .cancelled
            default: old == .done || old == .cancelled ? .reopened : .edited
            }
            return [TaskEvent(at: now, taskId: id, type: type, field: "status", old: old.rawValue, new: status.rawValue, actor: actor)]
        }
    }

    public func reschedule(_ id: String, to day: String, actor: Actor, reason: String? = nil) throws {
        let now = clock.now()
        try mutate(id, actor: actor, reason: reason) { t in
            let old = effectiveDay(t)
            guard old != day else { return [] }
            t.scheduled = day
            return [TaskEvent(at: now, taskId: id, type: .rescheduled, field: "scheduled", old: old, new: day, actor: actor)]
        }
    }

    public func setPriority(_ id: String, _ p: Priority, actor: Actor) throws {
        let now = clock.now()
        try mutate(id, actor: actor) { t in
            guard t.priority != p || t.priorityFromLegacy else { return [] }
            let old = t.priority
            t.priority = p
            t.priorityFromLegacy = false
            return [TaskEvent(at: now, taskId: id, type: .priorityChanged, field: "priority", old: "\(old.rawValue)", new: "\(p.rawValue)", actor: actor)]
        }
    }

    public func setEstimate(_ id: String, sessions: Int, actor: Actor) throws {
        let now = clock.now()
        try mutate(id, actor: actor) { t in
            guard t.estimateSessions != sessions else { return [] }
            let old = t.estimateSessions.map(String.init)
            t.estimateSessions = sessions
            return [TaskEvent(at: now, taskId: id, type: .estimateChanged, field: "est", old: old, new: "\(sessions)", actor: actor)]
        }
    }

    /// Adds a tag such as `later` (no-op if present).
    public func addTag(_ id: String, _ tag: String, actor: Actor) throws {
        let now = clock.now()
        try mutate(id, actor: actor) { t in
            guard !t.tags.contains(where: { $0.lowercased() == tag.lowercased() }) else { return [] }
            t.description += " #\(tag)"
            return [TaskEvent(at: now, taskId: id, type: .edited, field: "tags", new: "#\(tag)", actor: actor)]
        }
    }

    /// Replaces the tag `#old` with `#new` on one task line (whole tags only: renaming `#code`
    /// leaves `#coding` alone). Case-insensitive.
    public func renameTag(_ id: String, from old: String, to new: String, actor: Actor) throws {
        let now = clock.now()
        let pattern = try NSRegularExpression(pattern: "(?<![\\w#])#" + NSRegularExpression.escapedPattern(for: old) + "(?![\\w/-])",
                                              options: .caseInsensitive)
        try mutate(id, actor: actor) { t in
            let ns = t.description as NSString
            let replaced = pattern.stringByReplacingMatches(in: t.description, range: NSRange(location: 0, length: ns.length),
                                                            withTemplate: NSRegularExpression.escapedTemplate(for: "#" + new))
            guard replaced != t.description else { return [] }
            t.description = replaced
            return [TaskEvent(at: now, taskId: id, type: .edited, field: "tags", old: "#\(old)", new: "#\(new)", actor: actor)]
        }
    }

    /// Sets `[sessions:: n]` to the number of completed focus sessions linked to the task.
    public func setActualSessions(_ id: String, _ n: Int) throws {
        try mutate(id, actor: .app) { t in
            t.actualSessions = n
            return []
        }
    }

    /// Appends a new task. Scheduled today or unscheduled → today's note; otherwise → Backlog with ⏳.
    @discardableResult
    public func create(_ draft: TaskItem, actor: Actor, reason: String? = nil) throws -> TaskItem {
        var t = draft
        let used = Set(scan().tasks.compactMap(\.taskID))
        var id = t.taskID ?? TaskLineParser.newID()
        while used.contains(id) { id = TaskLineParser.newID() }
        t.taskID = id
        t.indent = ""
        if t.created == nil { t.created = today }
        let toToday = t.scheduled == nil || t.scheduled == today
        if toToday { t.scheduled = nil }
        let url = toToday ? config.dailyNote(today) : config.backlog
        t.file = config.relativePath(url)
        let line = TaskLineParser.serialize(t)
        if toToday {
            try SafeFile.appendToSection("## Today's task list", line: line, in: url,
                                         fileHeader: DailyNote.header(day: today, calendar: calendar))
        } else {
            try SafeFile.appendToSection("## Tasks", line: line, in: url, fileHeader: ["# Backlog", ""])
        }
        try events.append(TaskEvent(at: clock.now(), taskId: id, type: .created, new: t.description, actor: actor, reason: reason), at: clock.now())
        return t
    }

    // MARK: Change history for edits made outside the app

    /// Events describing what changed between two scans, credited to `actor`.
    public static func diff(old: [TaskItem], new: [TaskItem], at: Date, actor: Actor = .external, defaultDay: (TaskItem) -> String?) -> [TaskEvent] {
        let before = Dictionary(old.compactMap { t in t.taskID.map { ($0, t) } }, uniquingKeysWith: { a, _ in a })
        var out: [TaskEvent] = []
        for t in new {
            guard let id = t.taskID else { continue }
            guard let o = before[id] else {
                out.append(TaskEvent(at: at, taskId: id, type: .created, new: t.description, actor: actor))
                continue
            }
            if o.status != t.status {
                let type: TaskEventType = t.status == .done ? .completed : t.status == .cancelled ? .cancelled : (o.status == .done || o.status == .cancelled ? .reopened : .edited)
                out.append(TaskEvent(at: at, taskId: id, type: type, field: "status", old: o.status.rawValue, new: t.status.rawValue, actor: actor))
            }
            let od = defaultDay(o), nd = defaultDay(t)
            if od != nd {
                out.append(TaskEvent(at: at, taskId: id, type: .rescheduled, field: "scheduled", old: od, new: nd, actor: actor))
            }
            if o.priority != t.priority {
                out.append(TaskEvent(at: at, taskId: id, type: .priorityChanged, field: "priority", old: "\(o.priority.rawValue)", new: "\(t.priority.rawValue)", actor: actor))
            }
            if o.estimateSessions != t.estimateSessions {
                out.append(TaskEvent(at: at, taskId: id, type: .estimateChanged, field: "est", old: o.estimateSessions.map(String.init), new: t.estimateSessions.map(String.init), actor: actor))
            }
            if o.description != t.description {
                out.append(TaskEvent(at: at, taskId: id, type: .edited, field: "description", old: o.description, new: t.description, actor: actor))
            }
        }
        return out
    }

    /// Rewrites `Problems.md` (removed when there are none).
    public func writeProblems(_ problems: [String]) throws {
        let fm = FileManager.default
        if problems.isEmpty {
            if fm.fileExists(atPath: config.problems.path) { try fm.removeItem(at: config.problems) }
            return
        }
        let text = (["# Problems", "", "PastelFocus couldn't fully read these lines. Fix them in place; nothing was deleted.", ""] + problems).joined(separator: "\n") + "\n"
        try SafeFile.writeIfChanged(text, to: config.problems)
    }
}

public enum DailyNote {
    public static func header(day: String, calendar: DayCalendar) -> [String] {
        ["---", "date: \(day)", "type: daily-career-plan", "---", "", "# Career Plan — \(calendar.longDayTitle(day))", ""]
    }
}
