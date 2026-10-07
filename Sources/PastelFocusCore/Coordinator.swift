import Foundation

/// Everything the app does, minus the UI. The app calls these methods from its file watcher,
/// timers and buttons; tests call them directly against a temp vault.
public final class Coordinator {
    public let config: VaultConfig
    public let calendar: DayCalendar
    public let clock: Clock
    public let supportDir: URL

    public let store: TaskStore
    public let recorder: SessionRecorder
    public let inbox: InboxProcessor
    public let engine: FocusEngine
    public let analytics: AnalyticsEngine
    public let suggestions: SuggestionEngine
    public let suggestionLog: JSONLLog<SuggestionRecord>
    public private(set) var index: IndexDatabase?

    /// Last scan, used to spot edits made outside the app.
    public private(set) var tasks: [TaskItem] = []
    public private(set) var insights: [Insight] = []
    public private(set) var problems: [String] = []

    public init(config: VaultConfig, calendar: DayCalendar = DayCalendar(), clock: Clock = SystemClock(),
                supportDir: URL = VaultConfig.defaultSupportDirectory, preset: FocusPreset = .classic) {
        self.config = config
        self.calendar = calendar
        self.clock = clock
        self.supportDir = supportDir
        store = TaskStore(config: config, calendar: calendar, clock: clock)
        recorder = SessionRecorder(config: config, calendar: calendar, store: store)
        inbox = InboxProcessor(store: store, calendar: calendar, clock: clock)
        engine = FocusEngine(clock: clock, preset: preset, tzName: calendar.timeZone.identifier)
        analytics = AnalyticsEngine(calendar: calendar)
        suggestionLog = JSONLLog(directory: config.logsDir, prefix: "suggestions", calendar: calendar)
        suggestions = SuggestionEngine(calendar: calendar, history: suggestionLog.readAll())
        index = try? IndexDatabase(url: supportDir.appendingPathComponent("index.sqlite"))
        restoreEngine()
        insights = loadInsightsCache()
    }

    public var today: String { calendar.day(clock.now()) }
    public var todayTasks: [TaskItem] { store.todayTasks(tasks) }

    // MARK: Sync with the vault

    /// Call on launch and whenever the vault changes. Logs outside edits, stamps IDs,
    /// applies Inbox commands and rewrites Now.md and Problems.md.
    @discardableResult
    public func refresh() -> [TaskEvent] {
        let firstRun = tasks.isEmpty
        try? store.stampMissingIDs()
        let result = store.scan()
        var external: [TaskEvent] = []
        if !firstRun {
            external = TaskStore.diff(old: tasks, new: result.tasks, at: clock.now(), defaultDay: store.effectiveDay)
            for e in external { try? store.events.append(e, at: e.at) }
        }
        tasks = result.tasks
        problems = result.problems
        try? store.writeProblems(problems)
        if (try? inbox.process()) ?? 0 > 0 { resync() }
        writeNow()
        return external
    }

    /// Re-reads tasks after the app itself changed them, without logging them as outside edits.
    public func resync() {
        let r = store.scan()
        tasks = r.tasks
        problems = r.problems
    }

    /// Runs an app-initiated change, then resyncs and updates the generated files.
    public func perform(_ change: (TaskStore) throws -> Void) rethrows {
        try change(store)
        resync()
        writeNow()
    }

    // MARK: Timer

    /// Starts focus on a task; returns a suggestion to show first, if any (shorter sessions).
    public func startFocus(task: TaskItem?, minutes: Int? = nil, stopwatch: Bool = false) throws {
        let ref = task.flatMap { t in t.taskID.map { TaskRef(id: $0, title: t.title, category: t.category) } }
        try engine.start(task: ref, minutes: minutes, stopwatch: stopwatch)
        if let id = ref?.id, let t = store.find(id), t.status == .todo { try? perform { try $0.setStatus(id, .inProgress, actor: .app) } }
        saveEngine()
        writeNow()
    }

    public func suggestionBeforeStart(minutes: Int) -> Suggestion? {
        suggestions.evaluate(.sessionStart(plannedMinutes: minutes), insights: insights, now: clock.now(), sessionRunning: engine.phase != .idle)
    }

    /// Persists a finished session and returns a suggestion to show now, if any.
    @discardableResult
    public func sessionEnded(_ record: SessionRecord) -> Suggestion? {
        try? recorder.record(record)
        resync()
        saveEngine()
        writeNow()
        guard record.kind == .focus else { return nil }
        let blocks = recorder.log.readAll().filter { $0.kind == .focus && calendar.day($0.startedAt) == today }.count
        return suggestions.evaluate(.sessionEnd(blocksToday: blocks), insights: insights, now: clock.now(), sessionRunning: engine.phase != .idle)
    }

    /// Call every second while something is running; handles natural completion and pause timeouts.
    public func tick() -> SessionRecord? {
        guard let r = engine.tick() else { return nil }
        return r
    }

    public func respond(to s: Suggestion, _ response: SuggestionResponse) {
        let r = suggestions.record(s, response, at: clock.now())
        try? suggestionLog.append(r, at: r.at)
    }

    func engineStateURL() -> URL { supportDir.appendingPathComponent("state.json") }

    public func saveEngine() {
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        try? e.encode(engine.snapshot).write(to: engineStateURL(), options: .atomic)
    }

    func restoreEngine() {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: engineStateURL()), let s = try? d.decode(FocusSnapshot.self, from: data) {
            engine.restore(s)
        }
    }

    // MARK: Generated files

    public func nowState(appRunning: Bool = true) -> Reports.NowState {
        Reports.NowState(appRunning: appRunning, phase: engine.phase, taskTitle: engine.active?.task?.title,
                         taskID: engine.active?.task?.id, kind: engine.active?.kind, remainingS: engine.remainingS,
                         plannedS: engine.active?.plannedS ?? engine.preset.focusMinutes * 60, pauses: engine.active?.pauses.count ?? 0,
                         stopwatch: engine.isStopwatch, elapsedS: engine.elapsedS)
    }

    /// Today's numbers. The single source for Now.md, the daily note's summary and the panels,
    /// so Hermes and the app always report the same counts.
    public struct DayTotals: Equatable {
        public var tasks: [TaskItem]
        public var done: Int { tasks.filter { $0.status == .done }.count }
        public var total: Int { tasks.count }
        public var rollup: DailyRollup
    }

    public func todayTotals() -> DayTotals {
        let day = today
        let rollup = Rollups.build(sessions: recorder.log.readAll().filter { calendar.day($0.startedAt) == day },
                                   events: store.events.readAll().filter { calendar.day($0.at) == day },
                                   calendar: calendar)[day] ?? DailyRollup(day: day)
        return DayTotals(tasks: todayTasks, rollup: rollup)
    }

    /// Rewrites everything Hermes reads about today: Now.md and today's note summary.
    /// Each file is written only when its content changes (the app watches these folders).
    public func writeNow(appRunning: Bool = true) {
        let totals = todayTotals()
        let text = Reports.now(nowState(appRunning: appRunning), today: totals.tasks, rollup: totals.rollup, updated: clock.now(), calendar: calendar)
        _ = try? SafeFile.writeIfChanged(text, to: config.now, ignoring: "_Written by PastelFocus. Updated")
        try? writeDailySummary(day: today, totals: totals)
    }

    public func garden() -> Garden {
        GardenBuilder.build(sessions: recorder.log.readAll(), events: store.events.readAll(), calendar: calendar, now: clock.now())
    }

    // MARK: Nightly

    /// Recomputes insights, Stats files, the daily summary and the private index.
    public func nightly() throws {
        let now = clock.now()
        let sessions = recorder.log.readAll()
        let events = store.events.readAll()
        resync()
        insights = analytics.insights(AnalyticsInput(sessions: sessions, events: events, tasks: tasks), now: now)
        saveInsightsCache()
        let first = sessions.filter { $0.kind == .focus }.map(\.startedAt).min().map(calendar.day)
        try FileManager.default.createDirectory(at: config.appDir, withIntermediateDirectories: true)
        try Reports.insights(insights, totalFocusSessions: sessions.filter { $0.kind == .focus }.count, since: first, updated: now, calendar: calendar)
            .write(to: config.insights, atomically: true, encoding: .utf8)

        let rollups = Rollups.build(sessions: sessions, events: events, calendar: calendar)
        try FileManager.default.createDirectory(at: config.statsDir, withIntermediateDirectories: true)
        let monday = calendar.weekStart(now)
        for weekStart in [calendar.addDays(-7, to: monday), monday] {
            let days = (0..<7).map { calendar.addDays($0, to: weekStart) }
            let label = calendar.isoWeek(calendar.startOfDay(weekStart)!)
            let periodSessions = sessions.filter { days.contains(calendar.day($0.startedAt)) }
            try Reports.stats(title: "Week \(label)", days: days, rollups: rollups, sessions: periodSessions)
                .write(to: config.statsDir.appendingPathComponent("\(label).md"), atomically: true, encoding: .utf8)
        }
        let month = calendar.month(now)
        var monthDays: [String] = []
        var d = month + "-01"
        while d.hasPrefix(month) { monthDays.append(d); d = calendar.addDays(1, to: d) }
        try Reports.stats(title: "Month \(month)", days: monthDays, rollups: rollups,
                          sessions: sessions.filter { calendar.month($0.startedAt) == month })
            .write(to: config.statsDir.appendingPathComponent("\(month).md"), atomically: true, encoding: .utf8)

        try writeDailySummary(day: today, totals: todayTotals())
        try index?.rebuild(tasks: tasks, sessions: sessions, events: events, insights: insights)
    }

    /// A generated `## PastelFocus summary` section at the end of the day's note. Uses the same
    /// totals as Now.md and is rewritten whenever they change, so the two never disagree.
    public func writeDailySummary(day: String, totals: DayTotals) throws {
        let url = config.dailyNote(day)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let r = totals.rollup
        let summary = ["## PastelFocus summary", "",
                       "_Generated by PastelFocus and kept in sync with PastelFocus/Now.md; edits here are overwritten._", "",
                       "- Tasks: \(totals.done) of \(totals.total) done (open tasks planned for today or earlier, plus tasks finished today)",
                       "- Focused: \(r.focusedS / 60) min · \(r.completed) finished, \(r.interrupted) interrupted",
                       "- Breaks: \(r.breaks) (NSDR \(r.nsdr)) · postponements: \(r.postponements)"]
        func apply(_ lines: inout [String]) {
            if let start = lines.firstIndex(of: "## PastelFocus summary") {
                var end = start + 1
                while end < lines.count, !lines[end].hasPrefix("## ") { end += 1 }
                lines.replaceSubrange(start..<end, with: summary + [""])
            } else {
                if let last = lines.last, !last.isEmpty { lines.append("") }
                lines += summary
            }
            while lines.last == "" { lines.removeLast() }
        }
        // Skip the write when nothing changed, so the file watcher isn't woken for nothing.
        var preview = SafeFile.readLines(url)
        let before = preview
        apply(&preview)
        guard preview != before else { return }
        try SafeFile.edit(url) { apply(&$0) }
    }

    func insightsCacheURL() -> URL { supportDir.appendingPathComponent("insights.json") }

    func saveInsightsCache() {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        try? e.encode(insights).write(to: insightsCacheURL(), options: .atomic)
    }

    func loadInsightsCache() -> [Insight] {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: insightsCacheURL()) else { return [] }
        return (try? d.decode([Insight].self, from: data)) ?? []
    }
}
