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

    /// Open one-time tasks planned for a later day, soonest first. Repeating tasks are left out, so
    /// a routine's future days never fill the list; undated Backlog tasks are left out too.
    public func upcomingTasks(_ all: [TaskItem]) -> [TaskItem] {
        let day = today
        return all.compactMap { t -> (String, TaskItem)? in
            guard t.indent.isEmpty || t.taskID != nil, t.status.isOpen, !t.isRepeating,
                  let d = effectiveDay(t), d > day else { return nil }
            return (d, t)
        }
        .enumerated().sorted { ($0.element.0, $0.offset) < ($1.element.0, $1.offset) }.map(\.element.1)
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
            if status.isOpen, t.progress == 100 { t.progress = nil }
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

    /// Records how much of the whole task is done (0–100). Reaching 100 completes the task, so it
    /// shows as done everywhere: Today, Now.md, the note and Hermes.
    public func setProgress(_ id: String, _ percent: Int, actor: Actor, reason: String? = nil) throws {
        let p = min(100, max(0, percent))
        let now = clock.now(), day = today
        try mutate(id, actor: actor, reason: reason) { t in
            var out: [TaskEvent] = []
            if t.progress != p {
                out.append(TaskEvent(at: now, taskId: id, type: .progressChanged, field: "progress", old: t.progress.map(String.init), new: "\(p)", actor: actor))
                t.progress = p
            }
            if p == 100, t.status != .done {
                out.append(TaskEvent(at: now, taskId: id, type: .completed, field: "status", old: t.status.rawValue, new: TaskStatus.done.rawValue, actor: actor))
                t.status = .done
                t.completed = day
            }
            return out
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

    /// Saves an edit made in the task editor. Only the fields the user changed (`edited` vs the
    /// `original` the editor opened with) are written, onto the line as it is now, so changes Hermes
    /// made meanwhile (say, a new session count) are kept. Notes are the plain bullets indented under
    /// the task. Returns the saved task.
    @discardableResult
    public func apply(_ id: String, from original: TaskItem, to edited: TaskItem, actor: Actor) throws -> TaskItem {
        guard let found = find(id) else { throw SafeFileError.lineNotFound("task 🆔 \(id)") }
        let url = config.url(forRelative: found.file)
        let now = clock.now(), day = today
        var before = found, after = found
        try SafeFile.edit(url) { lines in
            guard let idx = lines.firstIndex(where: { TaskLineParser.parse($0)?.taskID == id }),
                  var t = TaskLineParser.parse(lines[idx], file: found.file, lineIndex: idx) else {
                throw SafeFileError.lineNotFound("task 🆔 \(id)")
            }
            // Notes: the run of plain bullets right under the line (as `parseFile` reads them).
            var end = idx + 1
            while end < lines.count, Self.indentWidth(lines[end]) > Self.indentWidth(lines[idx]),
                  !TaskLineParser.isTaskLine(lines[end]), lines[end].trimmingCharacters(in: .whitespaces).hasPrefix("- ") { end += 1 }
            let noteIndent = end > idx + 1 ? String(lines[idx + 1].prefix { $0 == " " || $0 == "\t" }) : t.indent + "    "
            t.notes = lines[(idx + 1)..<end].map { String($0.trimmingCharacters(in: .whitespaces).dropFirst(2)) }
            before = t

            if edited.description != original.description {
                t.description = edited.description
                // The legacy `**P1 · 90 min**` marker is gone once the text is rewritten, so write the
                // priority as an emoji instead.
                if TaskLineParser.stripLegacyMarker(t.description) == t.description { t.priorityFromLegacy = false }
            }
            if edited.progress != original.progress { t.progress = edited.progress }
            if edited.status != original.status {
                t.status = edited.status
                t.completed = edited.status == .done ? (t.completed ?? day) : nil
            }
            // Same rule as `setProgress`: 100% is done; reopening a 100% task clears it.
            if t.progress == 100, t.status != .done, edited.progress != original.progress {
                t.status = .done
                t.completed = t.completed ?? day
            } else if t.status.isOpen, t.progress == 100 { t.progress = nil }
            if edited.priority != original.priority { t.priority = edited.priority; t.priorityFromLegacy = false }
            if edited.scheduled != original.scheduled { t.scheduled = edited.scheduled }
            if edited.due != original.due { t.due = edited.due }
            if edited.start != original.start { t.start = edited.start }
            if edited.recurrence != original.recurrence { t.recurrence = edited.recurrence }
            if edited.notes != original.notes { t.notes = edited.notes.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }

            lines[idx] = TaskLineParser.serialize(t)
            if t.notes != before.notes {
                lines.replaceSubrange((idx + 1)..<end, with: t.notes.map { noteIndent + "- " + $0 })
            }
            after = t
        }
        var newEvents = Self.diff(old: [before], new: [after], at: now, actor: actor, defaultDay: effectiveDay)
        if before.due != after.due { newEvents.append(TaskEvent(at: now, taskId: id, type: .edited, field: "due", old: before.due, new: after.due, actor: actor)) }
        if before.start != after.start { newEvents.append(TaskEvent(at: now, taskId: id, type: .edited, field: "start", old: before.start, new: after.start, actor: actor)) }
        if before.notes != after.notes {
            newEvents.append(TaskEvent(at: now, taskId: id, type: .edited, field: "notes", old: before.notes.joined(separator: "\n"),
                                       new: after.notes.joined(separator: "\n"), actor: actor))
        }
        for e in newEvents { try events.append(e, at: now) }
        return after
    }

    /// What `delete` removed, so it can be put back (Undo).
    public struct DeletedTask: Equatable, Sendable {
        public var task: TaskItem
        /// Vault-relative file and the index of the task line when it was removed.
        public var file: String
        public var lineIndex: Int
        /// The task line plus everything indented under it (notes and subtasks).
        public var lines: [String]
    }

    /// Removes a task's line, and the notes and subtasks indented under it, from its note.
    @discardableResult
    public func delete(_ id: String, actor: Actor, reason: String? = nil) throws -> DeletedTask {
        guard let found = find(id) else { throw SafeFileError.lineNotFound("task 🆔 \(id)") }
        let url = config.url(forRelative: found.file)
        var removed = DeletedTask(task: found, file: found.file, lineIndex: found.lineIndex, lines: [])
        try SafeFile.edit(url) { lines in
            guard let idx = lines.firstIndex(where: { TaskLineParser.parse($0)?.taskID == id }) else {
                throw SafeFileError.lineNotFound("task 🆔 \(id)")
            }
            let indent = Self.indentWidth(lines[idx])
            var end = idx + 1
            while end < lines.count, !lines[end].trimmingCharacters(in: .whitespaces).isEmpty, Self.indentWidth(lines[end]) > indent { end += 1 }
            removed.lineIndex = idx
            removed.lines = Array(lines[idx..<end])
            lines.removeSubrange(idx..<end)
        }
        try events.append(TaskEvent(at: clock.now(), taskId: id, type: .deleted, old: found.description, actor: actor, reason: reason), at: clock.now())
        return removed
    }

    /// Puts a deleted task back where it was (or at the end of the note if that has since shrunk).
    public func restore(_ d: DeletedTask, actor: Actor) throws {
        guard let id = d.task.taskID, find(id) == nil else { return }
        try SafeFile.edit(config.url(forRelative: d.file)) { lines in
            lines.insert(contentsOf: d.lines, at: min(d.lineIndex, lines.count))
        }
        try events.append(TaskEvent(at: clock.now(), taskId: id, type: .created, new: d.task.description, actor: actor, reason: "restored"), at: clock.now())
    }

    static func indentWidth(_ line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
    }

    /// Sets `[spent:: …]` to the minutes of focus logged on the task. Leaves the line alone when
    /// it already says that.
    public func setSpent(_ id: String, minutes: Int) throws {
        guard let t = find(id), t.spentMinutes != minutes || t.hasLegacyTimeFields else { return }
        try mutate(id, actor: .app) { t in
            t.spentMinutes = minutes
            return []
        }
    }

    /// One-time move from session counts to time: every line still carrying `[est:: N]` or
    /// `[sessions:: N]` gets `[spent:: …]` instead. The time is what the sessions log holds for the
    /// task, or N × 25 min for an old count the log knows nothing about; estimates are dropped.
    /// Each file is copied to `backupDir` before it changes. Returns how many lines changed.
    @discardableResult
    public func migrateLegacyTimeFields(spentByTask: [String: Int], backupDir: URL) throws -> Int {
        var count = 0
        for url in taskFiles() {
            let lines = SafeFile.readLines(url)
            guard lines.contains(where: { TaskLineParser.parse($0)?.hasLegacyTimeFields == true }) else { continue }
            let rel = config.relativePath(url)
            let backup = backupDir.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: backup.path) { try FileManager.default.copyItem(at: url, to: backup) }
            try SafeFile.edit(url) { lines in
                for (i, line) in lines.enumerated() {
                    guard var t = TaskLineParser.parse(line), t.hasLegacyTimeFields else { continue }
                    let logged = t.taskID.flatMap { spentByTask[$0] } ?? 0
                    let counted = (t.legacySessions ?? 0) * TaskLineParser.minutesPerSession
                    let minutes = logged > 0 ? logged : counted
                    t.spentMinutes = minutes > 0 ? minutes : t.spentMinutes
                    t.legacyEstimate = nil
                    t.legacySessions = nil
                    lines[i] = TaskLineParser.serialize(t)
                    count += 1
                }
            }
        }
        return count
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
