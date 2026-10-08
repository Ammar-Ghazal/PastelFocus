import AppKit
import Combine
import PastelFocusCore
import ServiceManagement
import SwiftUI

enum TaskFilter: String, CaseIterable { case all = "All", focus = "Focus", later = "Later", done = "Done" }

/// Values that change every second while a session runs. Kept out of `AppModel` so only the
/// Focus panel and the menu-bar label redraw each second, not the Today list or the garden.
@MainActor
final class TickState: ObservableObject {
    @Published var remainingS = 25 * 60
    @Published var elapsedS = 0
}

struct UndoToast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let undo: () -> Void
    static func == (a: UndoToast, b: UndoToast) -> Bool { a.id == b.id }
}

/// Main-thread model: owns the Coordinator and turns its state into published values for the panels.
@MainActor
final class AppModel: ObservableObject {
    let settings: AppSettings
    private(set) var coordinator: Coordinator

    @Published var tasks: [TaskItem] = []
    @Published var filter: TaskFilter = .all
    @Published var phase: FocusPhase = .idle
    @Published var plannedS = 25 * 60
    let ticks = TickState()
    var remainingS: Int {
        get { ticks.remainingS }
        set { if ticks.remainingS != newValue { ticks.remainingS = newValue } }
    }
    var elapsedS: Int {
        get { ticks.elapsedS }
        set { if ticks.elapsedS != newValue { ticks.elapsedS = newValue } }
    }
    @Published var isStopwatch = false
    @Published var activeTitle: String?
    @Published var activeKind: SessionKind?
    @Published var selectedTaskID: String?
    @Published var suggestion: Suggestion?
    @Published var lastEnded: SessionRecord?
    @Published var garden: Garden = .empty
    /// Tags and the plant slot each grows (PastelFocus/Tags.md).
    @Published var tags = TagRegistry()
    @Published var insights: [Insight] = []
    @Published var toast: UndoToast?
    @Published var problemsCount = 0
    @Published var todayFocusedMin = 0
    @Published var hermesCard: (TaskItem, Int, String?)? = nil
    /// The theme on screen: the user's choice, matched to macOS light/dark if they asked for that.
    @Published private(set) var theme = Theme.standard

    private var watcher: FileWatcher?
    private var ticker: Timer?
    private var minuteTimer: Timer?
    private var hotKeys: HotKeys?
    let notifier = Notifier()
    private let editors = TaskEditorWindows()
    private var sleepStart: Date?
    private var refreshPending = false
    private var bag: Set<AnyCancellable> = []
    private var lastNightlyDay: String? { get { UserDefaults.standard.string(forKey: "lastNightly") } set { UserDefaults.standard.set(newValue, forKey: "lastNightly") } }

    init(settings: AppSettings) {
        self.settings = settings
        coordinator = Coordinator(config: settings.vaultConfig, supportDir: settings.supportDir, preset: settings.preset)
        coordinator.goodDayMinutes = settings.goodDayMinutes
        coordinator.inbox.actions = self
        notifier.onAction = { [weak self] action, info in self?.handleNotification(action, info: info) }
        if AppSettings.devName == nil { hotKeys = HotKeys(startPause: { [weak self] in self?.startPauseShortcut() }, stop: { [weak self] in self?.stop(reason: nil) }) }
        observeSystem()
        applyTheme()
        settings.$themeSelection.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.applyTheme() } }.store(in: &bag)
        settings.$ambientMotion.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.objectWillChange.send() } }.store(in: &bag)
        settings.$matchSystemAppearance.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.applyTheme() } }.store(in: &bag)
        DistributedNotificationCenter.default().addObserver(forName: .init("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyTheme() }
        }
        settings.$focusMinutes.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.coordinator.engine.preset = settings.preset; self?.publish() } }.store(in: &bag)
        // A new good-day threshold changes the streak, landmarks and the Stats files Hermes reads.
        settings.$goodDayMinutes.dropFirst().removeDuplicates().debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] m in self?.coordinator.goodDayMinutes = m; self?.runNightly() }.store(in: &bag)
        settings.$taskSort.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.publish() } }.store(in: &bag)
        settings.$logsInVault.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.rebuildCoordinator() } }.store(in: &bag)
        settings.$vaultPath.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.rebuildCoordinator() } }.store(in: &bag)
        start()
    }

    // MARK: Theme

    func applyTheme() {
        let systemDark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let (definition, palette) = ThemeCatalog.resolve(settings.themeSelection, matchSystem: settings.matchSystemAppearance,
                                                         systemDark: systemDark)
        let next = Theme(definition, palette)
        guard next.palette.id != theme.palette.id else { return }
        theme = next
        coordinator.writeNow()
        publish()
    }

    func selectTheme(_ id: String) {
        guard let t = ThemeCatalog.theme(id), id != settings.themeSelection.themeID else { return }
        // Keep the mood: pick the new theme's palette closest to the current accent and mode.
        let current = theme.palette
        let best = t.palettes.min { a, b in
            (a.isDark == current.isDark ? 0 : 1, OKLCH(a.accent).distance(to: OKLCH(current.accent)))
                < (b.isDark == current.isDark ? 0 : 1, OKLCH(b.accent).distance(to: OKLCH(current.accent)))
        } ?? t.defaultPalette
        settings.themeSelection = ThemeSelection(themeID: id, paletteID: best.id)
    }

    /// Steps through the current theme's colour combos (menu bar).
    func cyclePalette(_ step: Int) {
        let t = ThemeCatalog.resolve(settings.themeSelection).0
        guard let i = t.palettes.firstIndex(where: { $0.id == settings.themeSelection.paletteID }) else { return }
        let next = t.palettes[(i + step + t.palettes.count) % t.palettes.count]
        selectPalette(next.id)
    }

    func selectPalette(_ id: String) {
        settings.themeSelection = ThemeSelection(themeID: settings.themeSelection.themeID, paletteID: id)
    }

    func rebuildCoordinator() {
        coordinator.writeNow(appRunning: false)
        coordinator = Coordinator(config: settings.vaultConfig, supportDir: settings.supportDir, preset: settings.preset)
        coordinator.goodDayMinutes = settings.goodDayMinutes
        coordinator.inbox.actions = self
        start()
    }

    private func start() {
        let c = coordinator.config
        for dir in [c.dailyDir, c.appDir] { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        watcher = FileWatcher(paths: [c.dailyDir.path, c.appDir.path]) { [weak self] in self?.scheduleRefresh() }
        refreshNow()
        if lastNightlyDay != coordinator.today { runNightly() }
        startTicker()
        minuteTimer?.invalidate()
        minuteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.minuteCheck() }
        }
        applyLoginItem()
    }

    // MARK: Refresh

    private func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.refreshPending = false
            self?.refreshNow()
        }
    }

    func refreshNow() {
        let before = coordinator.store.events.readAll().count
        coordinator.refresh()
        let newEvents = coordinator.store.events.readAll().dropFirst(before)
        if let e = newEvents.last(where: { $0.actor == .hermes }) { offerUndo(for: e) }
        publish()
    }

    func publish() {
        let c = coordinator
        tasks = settings.taskSort.sorted(c.todayTasks)
        problemsCount = c.problems.count
        phase = c.engine.phase
        remainingS = c.engine.remainingS
        plannedS = c.engine.active?.plannedS ?? c.engine.preset.focusMinutes * 60
        activeTitle = c.engine.active?.task?.title
        elapsedS = c.engine.elapsedS
        isStopwatch = c.engine.isStopwatch
        activeKind = c.engine.active?.kind
        insights = c.insights
        garden = c.garden()
        tags = c.tagRegistry
        // Same totals as Now.md and the note's summary, so the menu bar never disagrees with Hermes.
        todayFocusedMin = c.todayTotals().rollup.focusedS / 60
        if selectedTaskID == nil || !tasks.contains(where: { $0.taskID == selectedTaskID && $0.status.isOpen }) {
            selectedTaskID = (tasks.first { $0.status.isOpen && $0.priority >= .high } ?? tasks.first { $0.status.isOpen })?.taskID
        }
    }

    var filteredTasks: [TaskItem] { tasks(for: filter) }

    func tasks(for f: TaskFilter) -> [TaskItem] {
        switch f {
        case .all: return tasks
        case .done: return tasks.filter { $0.status == .done }
        case .later: return tasks.filter(\.isLater)
        case .focus: return tasks.filter { $0.status.isOpen && ($0.tags.contains { $0.lowercased() == "focus" } || $0.priority >= .high) }
        }
    }

    func count(_ f: TaskFilter) -> Int { tasks(for: f).count }

    /// The first unfinished urgent or high-priority task in the list gets the highlighted row.
    var highlightedID: String? { tasks.first { $0.status.isOpen && $0.priority >= .high }?.taskID }

    // MARK: Tags

    /// Resolves tags to plants in the current theme (shared with the views through the environment).
    var plantArt: PlantArt { PlantArt(registry: tags, theme: theme.definition.id) }

    /// How many of all scanned tasks (any day) carry each tag.
    func taskCount(tagged name: String) -> Int { coordinator.tasks(tagged: name).count }

    /// Runs a tag change, refreshes, and shows the error (if any) as a toast. Returns success.
    @discardableResult
    func changeTags(_ change: (Coordinator) throws -> Void) -> Bool {
        do { try change(coordinator); publish(); return true }
        catch { toast = UndoToast(text: "\(error)", undo: {}); return false }
    }

    // MARK: Task actions

    func toggle(_ t: TaskItem) {
        guard let id = t.taskID else { return }
        let target: TaskStatus = t.status == .done ? .todo : .done
        do {
            try coordinator.perform { try $0.setStatus(id, target, actor: .you) }
            toast = UndoToast(text: target == .done ? "Marked \"\(t.title)\" done" : "Reopened \"\(t.title)\"") { [weak self] in
                try? self?.coordinator.perform { try $0.setStatus(id, t.status, actor: .you) }
                self?.publish()
            }
        } catch { toast = UndoToast(text: "\(error)", undo: {}) }
        publish()
    }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var draft = TaskLineParser.parse("- [ ] " + trimmed) ?? TaskItem(description: trimmed)
        if draft.tags.isEmpty { draft.description += " #focus" }
        try? coordinator.perform { _ = try $0.create(draft, actor: .you) }
        publish()
        if let created = tasks.last, let s = coordinator.suggestions.evaluate(.planning(created), insights: insights, now: Date(), sessionRunning: phase != .idle) {
            present(s)
        }
    }

    func setPriority(_ t: TaskItem, _ p: Priority) {
        guard let id = t.taskID else { return }
        try? coordinator.perform { try $0.setPriority(id, p, actor: .you) }
        publish()
    }

    /// Opens the task in its own editor window.
    func edit(_ t: TaskItem) { editors.open(t, model: self) }

    /// Saves the editor's changes (only the fields changed there). Returns an error message, or nil.
    func saveEdit(_ original: TaskItem, _ edited: TaskItem) -> String? {
        guard let id = original.taskID else { return "This task has no 🆔 yet" }
        do {
            try coordinator.perform { try $0.apply(id, from: original, to: edited, actor: .you) }
            publish()
            return nil
        } catch { return "\(error)" }
    }

    /// Removes the task's line from the vault, with Undo.
    func delete(_ t: TaskItem) {
        guard let id = t.taskID else { return }
        do {
            var removed: TaskStore.DeletedTask?
            try coordinator.perform { removed = try $0.delete(id, actor: .you) }
            if selectedTaskID == id { selectedTaskID = nil }
            toast = UndoToast(text: "Deleted \"\(t.title)\"") { [weak self] in
                guard let self, let removed else { return }
                try? self.coordinator.perform { try $0.restore(removed, actor: .you) }
                self.publish()
            }
        } catch { toast = UndoToast(text: "\(error)", undo: {}) }
        publish()
    }

    func moveToLater(_ t: TaskItem) {
        guard let id = t.taskID else { return }
        try? coordinator.perform { try $0.addTag(id, "later", actor: .you) }
        publish()
    }

    func openInObsidian(_ t: TaskItem) {
        let vault = URL(fileURLWithPath: settings.vaultPath).lastPathComponent
        var comps = URLComponents(string: "obsidian://open")!
        comps.queryItems = [URLQueryItem(name: "vault", value: vault), URLQueryItem(name: "file", value: t.file)]
        if let url = comps.url { NSWorkspace.shared.open(url) }
    }

    func createTodayNote() {
        let url = coordinator.config.dailyNote(coordinator.today)
        try? SafeFile.edit(url) { lines in
            if lines.isEmpty { lines = DailyNote.header(day: coordinator.today, calendar: coordinator.calendar) + ["## Today's task list", ""] }
        }
        refreshNow()
    }

    /// Undo for changes Hermes made through the Inbox.
    private func offerUndo(for e: TaskEvent) {
        let title = coordinator.store.find(e.taskId)?.title ?? e.taskId
        let store = coordinator.store
        let undo: (() -> Void)?
        switch e.type {
        case .completed, .cancelled: undo = { try? store.setStatus(e.taskId, .todo, actor: .you) }
        case .reopened: undo = { try? store.setStatus(e.taskId, .done, actor: .you) }
        case .rescheduled: undo = e.old.map { old in { try? store.reschedule(e.taskId, to: old, actor: .you, reason: "undo") } }
        case .priorityChanged: undo = e.old.flatMap(Int.init).flatMap(Priority.init(rawValue:)).map { p in { try? store.setPriority(e.taskId, p, actor: .you) } }
        case .estimateChanged: undo = e.old.flatMap(Int.init).map { n in { try? store.setEstimate(e.taskId, sessions: n, actor: .you) } }
        case .created: undo = { try? store.setStatus(e.taskId, .cancelled, actor: .you, reason: "undo") }
        default: undo = nil
        }
        guard let undo else { return }
        let verb = e.type.rawValue.replacingOccurrences(of: "_", with: " ")
        toast = UndoToast(text: "Hermes \(verb) \"\(title)\"") { [weak self] in
            undo()
            self?.coordinator.resync()
            self?.publish()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            if self?.toast?.text.hasPrefix("Hermes") == true { self?.toast = nil }
        }
    }

    // MARK: Timer

    var selectedTask: TaskItem? { tasks.first { $0.taskID == selectedTaskID } }
    var openTasks: [TaskItem] { tasks.filter { $0.status.isOpen } }

    func startFocus(on task: TaskItem? = nil, minutes: Int? = nil, skipSuggestion: Bool = false) {
        let t = task ?? selectedTask
        selectedTaskID = t?.taskID ?? selectedTaskID
        let mins = minutes ?? coordinator.engine.preset.focusMinutes
        if !skipSuggestion, !settings.stopwatchMode, let s = coordinator.suggestionBeforeStart(minutes: mins) {
            present(s)
            return
        }
        do {
            try coordinator.startFocus(task: t, minutes: mins, stopwatch: settings.stopwatchMode && minutes == nil)
            scheduleEndNotification()
        } catch { toast = UndoToast(text: "A session is already running", undo: {}) }
        publish()
    }

    /// Set from the dial. Only stored; the engine picks it up through the settings subscription.
    func setFocusMinutes(_ m: Int) {
        let clamped = DialMath.clamp(m)
        guard clamped != settings.focusMinutes else { return }
        settings.focusMinutes = clamped
    }

    func pause() { try? coordinator.engine.pause(); notifier.cancel(id: "session-end"); coordinator.saveEngine(); coordinator.writeNow(); publish() }
    func resume() { try? coordinator.engine.resume(); scheduleEndNotification(); coordinator.saveEngine(); coordinator.writeNow(); publish() }

    func stop(reason: String?) {
        guard phase != .idle, let r = try? coordinator.engine.stop(reason: reason) else { return }
        notifier.cancel(id: "session-end")
        ended(r)
        if reason == "done early", let id = r.taskId { try? coordinator.perform { try $0.setStatus(id, .done, actor: .you) } }
        publish()
    }

    func startRest(kind: SessionKind? = nil, minutes: Int? = nil) {
        try? coordinator.engine.startRest(kind: kind, minutes: minutes)
        coordinator.saveEngine()
        coordinator.writeNow()
        scheduleEndNotification()
        if coordinator.engine.active?.kind == .nsdr, !settings.nsdrAudio.isEmpty {
            let s = settings.nsdrAudio
            NSWorkspace.shared.open(s.hasPrefix("/") ? URL(fileURLWithPath: s) : (URL(string: s) ?? URL(fileURLWithPath: s)))
        }
        publish()
    }

    func startPauseShortcut() {
        switch phase {
        case .idle: startFocus(skipSuggestion: true)
        case .running: pause()
        case .paused: resume()
        case .resting: break
        }
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickOnce() }
        }
        ticker?.tolerance = 0.2
    }

    private func tickOnce() {
        guard coordinator.engine.phase != .idle else { return }
        if let r = coordinator.tick() { ended(r) }
        remainingS = coordinator.engine.remainingS
        elapsedS = coordinator.engine.elapsedS
        // Assigning an unchanged @Published value still redraws every observer, so compare first.
        if phase != coordinator.engine.phase { phase = coordinator.engine.phase }
    }

    private func ended(_ r: SessionRecord) {
        lastEnded = r
        if let s = coordinator.sessionEnded(r) { present(s) }
        publish()
    }

    private func scheduleEndNotification() {
        guard let end = coordinator.engine.countdownEnd, let a = coordinator.engine.active else { return }
        let isFocus = a.kind == .focus
        notifier.schedule(id: "session-end", title: isFocus ? "Focus complete ✦" : "Rest is over",
                          body: isFocus ? (a.task?.title ?? "Unassigned focus") : "Ready for the next block?",
                          at: end, info: ["taskID": a.task?.id ?? "", "kind": a.kind.rawValue])
    }

    private func handleNotification(_ action: String, info: [AnyHashable: Any]) {
        switch action {
        case "markDone":
            if let id = info["taskID"] as? String, !id.isEmpty { try? coordinator.perform { try $0.setStatus(id, .done, actor: .you) }; publish() }
        case "startRest": startRest()
        default: break
        }
    }

    // MARK: Suggestions

    func present(_ s: Suggestion) {
        suggestion = s
        coordinator.respond(to: s, .shown)
    }

    func answer(_ response: SuggestionResponse) {
        guard let s = suggestion else { return }
        coordinator.respond(to: s, response)
        suggestion = nil
        guard response == .accepted else { return }
        switch s.action {
        case .useShorterSessions(let m): startFocus(minutes: m, skipSuggestion: true)
        case .takeBreak(let kind, let m): startRest(kind: kind, minutes: m)
        case .raiseEstimate(let id, let n): try? coordinator.perform { try $0.setEstimate(id, sessions: n, actor: .you) }; publish()
        case .splitOrDrop(let id): if let t = coordinator.store.find(id) { openInObsidian(t) }
        }
    }

    // MARK: System events

    private func observeSystem() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sleepStart = Date() }
        }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let from = self.sleepStart, let r = self.coordinator.engine.handleSleep(from: from, to: Date()) {
                    self.notifier.cancel(id: "session-end")
                    self.ended(r)
                }
                self.sleepStart = nil
                self.minuteCheck()
                self.refreshNow()
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.coordinator.saveEngine()
                self?.coordinator.writeNow(appRunning: false)
            }
        }
    }

    /// Nightly pass at first wake after midnight, plus an evening refresh of the daily summary at 21:00.
    private func minuteCheck() {
        let cal = coordinator.calendar
        let now = Date()
        if lastNightlyDay != coordinator.today || (cal.hour(now) == 21 && cal.minuteOfDay(now) % 60 == 0) {
            runNightly()
        }
        coordinator.writeNow()
    }

    func runNightly() {
        let previous = lastNightlyDay
        do {
            try coordinator.nightly()
            lastNightlyDay = coordinator.today
        } catch {
            toast = UndoToast(text: "Nightly analysis failed: \(error)", undo: {})
        }
        // New month: save last month's postcard.
        if let p = previous, p.prefix(7) != coordinator.today.prefix(7) { savePostcard(.month, containing: p) }
        publish()
    }

    /// Saves a period's garden (this month by default) as PastelFocus/Garden/<period>.png,
    /// e.g. 2026-10.png, 2026-W41.png or 2026-10-07.png.
    func savePostcard(_ period: GardenPeriod = .month, containing day: String? = nil) {
        let plot = garden.plot(period, containing: day ?? coordinator.today, calendar: coordinator.calendar)
        let m = plot.key
        let view = PostcardView(title: m, plot: plot, garden: garden).environment(\.theme, theme).environment(\.plantArt, plantArt)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        let dir = coordinator.config.gardenDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? png.write(to: dir.appendingPathComponent("\(m).png"))
        toast = UndoToast(text: "Saved postcard to PastelFocus/Garden/\(m).png", undo: {})
    }

    private func applyLoginItem() {
        guard AppSettings.devName == nil else { return } // dev instances never become login items
        let service = SMAppService.mainApp
        if settings.launchAtLogin, service.status != .enabled { try? service.register() }
        if !settings.launchAtLogin, service.status == .enabled { try? service.unregister() }
    }
}

// MARK: Inbox actions from Hermes

extension AppModel: FocusActions {
    nonisolated func suggestFocus(task: TaskItem, minutes: Int, why: String?) -> Bool {
        MainActor.assumeIsolated {
            guard phase == .idle else { return false }
            hermesCard = (task, minutes, why)
            return true
        }
    }

    nonisolated func startFocus(task: TaskItem, minutes: Int) -> String? {
        MainActor.assumeIsolated {
            guard settings.allowHermesStart else { return "Hermes isn't allowed to start sessions (PastelFocus Settings)" }
            guard phase == .idle else { return "a session is already running" }
            startFocus(on: task, minutes: minutes, skipSuggestion: true)
            return nil
        }
    }
}
