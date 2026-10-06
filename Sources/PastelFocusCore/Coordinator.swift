import Foundation

/// Everything the app does, minus the UI. The app calls these methods from its file watcher,
/// timers and buttons; tests call them directly against a temp vault.
public final class Coordinator {
    public let config: VaultConfig
    public let calendar: DayCalendar
    public let clock: Clock
    public let supportDir: URL
    public let widgetDir: URL?

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
    /// Bumped each time the widget snapshot actually changes, so the app reloads widgets only then.
    public private(set) var widgetVersion = 0

    public init(config: VaultConfig, calendar: DayCalendar = DayCalendar(), clock: Clock = SystemClock(),
                supportDir: URL = VaultConfig.defaultSupportDirectory, widgetDir: URL? = WidgetBridge.container,
                preset: FocusPreset = .classic) {
        self.config = config
        self.calendar = calendar
        self.clock = clock
        self.supportDir = supportDir
        self.widgetDir = widgetDir
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
    /// applies Inbox commands and rewrites Now.md, Problems.md and the widget snapshot.
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

    public func writeNow(appRunning: Bool = true) {
        let sessions = recorder.log.readAll()
        let rollup = Rollups.build(sessions: sessions.filter { calendar.day($0.startedAt) == today },
                                   events: store.events.readAll().filter { calendar.day($0.at) == today }, calendar: calendar)[today]
        let text = Reports.now(nowState(appRunning: appRunning), today: todayTasks, rollup: rollup, updated: clock.now(), calendar: calendar)
        // The app watches this folder, so skip writes that would only change the timestamp.
        _ = try? SafeFile.writeIfChanged(text, to: config.now, ignoring: "_Written by PastelFocus. Updated")
        writeWidgetSnapshot(focusedToday: rollup?.focusedS ?? 0)
    }

    public func writeWidgetSnapshot(focusedToday: Int) {
        guard let dir = widgetDir else { return }
        let rows = todayTasks.compactMap { t -> WidgetSnapshot.Row? in
            guard let id = t.taskID else { return nil }
            return WidgetSnapshot.Row(id: id, title: t.title, tag: t.priority == .high ? "High" : t.category?.capitalized,
                                      done: t.status == .done, high: t.priority == .high)
        }
        let next = rows.first { !$0.done && $0.high } ?? rows.first { !$0.done }
        var snap = WidgetSnapshot(updated: clock.now(), tasks: rows, doneCount: rows.filter(\.done).count, totalCount: rows.count,
                                  phase: engine.phase, timerTitle: engine.active?.task?.title ?? (engine.phase == .resting ? "Rest" : "Pick a task"),
                                  timerEnd: engine.countdownEnd, remainingS: engine.remainingS, nextTask: next,
                                  focusedMinutesToday: focusedToday / 60, goodDays: garden().goodDays)
        snap.timerStart = engine.stopwatchStart
        snap.elapsedS = engine.isStopwatch ? engine.elapsedS : nil
        var unchanged = WidgetBridge.read(from: dir)
        unchanged.updated = snap.updated
        if unchanged == snap { return }
        try? WidgetBridge.write(snap, to: dir)
        widgetVersion += 1
    }

    /// Applies taps queued by the widgets.
    public func drainWidgetCommands() {
        guard let dir = widgetDir else { return }
        for c in WidgetBridge.drain(in: dir) {
            switch c.action {
            case .toggleTask:
                guard let id = c.taskID, let t = store.find(id) else { continue }
                try? perform { try $0.setStatus(id, t.status == .done ? .todo : .done, actor: .you) }
            case .startFocus:
                let t = c.taskID.flatMap { store.find($0) }
                try? startFocus(task: t)
            case .pauseFocus: try? engine.pause(); saveEngine(); writeNow()
            case .resumeFocus: try? engine.resume(); saveEngine(); writeNow()
            }
        }
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

        try writeDailySummary(day: today, rollups: rollups)
        try index?.rebuild(tasks: tasks, sessions: sessions, events: events, insights: insights)
    }

    /// A generated `## PastelFocus summary` section at the end of the day's note, replaced each time.
    public func writeDailySummary(day: String, rollups: [String: DailyRollup]) throws {
        let url = config.dailyNote(day)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let r = rollups[day] ?? DailyRollup(day: day)
        let dayTasks = tasks.filter { store.effectiveDay($0) == day || $0.completed == day }
        let summary = ["## PastelFocus summary", "",
                       "_Generated by PastelFocus; edits here are overwritten._", "",
                       "- Tasks done: \(dayTasks.filter { $0.status == .done }.count) of \(dayTasks.count)",
                       "- Focused: \(r.focusedS / 60) min · \(r.completed) finished, \(r.interrupted) interrupted",
                       "- Breaks: \(r.breaks) (NSDR \(r.nsdr)) · postponements: \(r.postponements)"]
        try SafeFile.edit(url) { lines in
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
