import AppKit
import Combine
import PastelFocusCore
import ServiceManagement
import SwiftUI
import WidgetKit

enum TaskFilter: String, CaseIterable { case all = "All", focus = "Focus", later = "Later", done = "Done" }

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
    @Published var remainingS = 25 * 60
    @Published var plannedS = 25 * 60
    @Published var activeTitle: String?
    @Published var activeKind: SessionKind?
    @Published var selectedTaskID: String?
    @Published var cycleIndex = 0
    @Published var suggestion: Suggestion?
    @Published var lastEnded: SessionRecord?
    @Published var garden: Garden = .empty
    @Published var insights: [Insight] = []
    @Published var toast: UndoToast?
    @Published var problemsCount = 0
    @Published var todayFocusedMin = 0
    @Published var sessionsToday: [SessionRecord] = []
    @Published var hermesCard: (TaskItem, Int, String?)? = nil

    private var watcher: FileWatcher?
    private var ticker: Timer?
    private var minuteTimer: Timer?
    private var hotKeys: HotKeys?
    let notifier = Notifier()
    private var sleepStart: Date?
    private var refreshPending = false
    private var bag: Set<AnyCancellable> = []
    private var lastNightlyDay: String? { get { UserDefaults.standard.string(forKey: "lastNightly") } set { UserDefaults.standard.set(newValue, forKey: "lastNightly") } }

    init(settings: AppSettings) {
        self.settings = settings
        coordinator = Coordinator(config: settings.vaultConfig, preset: settings.preset)
        coordinator.inbox.actions = self
        notifier.onAction = { [weak self] action, info in self?.handleNotification(action, info: info) }
        hotKeys = HotKeys(startPause: { [weak self] in self?.startPauseShortcut() }, stop: { [weak self] in self?.stop(reason: nil) })
        observeSystem()
        settings.$presetName.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.coordinator.engine.preset = settings.preset; self?.publish() } }.store(in: &bag)
        settings.$logsInVault.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.rebuildCoordinator() } }.store(in: &bag)
        settings.$vaultPath.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.rebuildCoordinator() } }.store(in: &bag)
        start()
    }

    func rebuildCoordinator() {
        coordinator.writeNow(appRunning: false)
        coordinator = Coordinator(config: settings.vaultConfig, preset: settings.preset)
        coordinator.inbox.actions = self
        start()
    }

    private func start() {
        let c = coordinator.config
        for dir in [c.dailyDir, c.appDir] { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        var paths = [c.dailyDir.path, c.appDir.path]
        if let w = coordinator.widgetDir { try? FileManager.default.createDirectory(at: w, withIntermediateDirectories: true); paths.append(w.path) }
        watcher = FileWatcher(paths: paths) { [weak self] in self?.scheduleRefresh() }
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
        coordinator.drainWidgetCommands()
        coordinator.refresh()
        let newEvents = coordinator.store.events.readAll().dropFirst(before)
        if let e = newEvents.last(where: { $0.actor == .hermes }) { offerUndo(for: e) }
        publish()
    }

    func publish() {
        let c = coordinator
        tasks = c.todayTasks
        problemsCount = c.problems.count
        phase = c.engine.phase
        remainingS = c.engine.remainingS
        plannedS = c.engine.active?.plannedS ?? c.engine.preset.focusMinutes * 60
        activeTitle = c.engine.active?.task?.title
        activeKind = c.engine.active?.kind
        cycleIndex = c.engine.cycleIndex
        insights = c.insights
        garden = c.garden()
        let all = c.recorder.log.readAll()
        sessionsToday = all.filter { c.calendar.day($0.startedAt) == c.today }
        todayFocusedMin = sessionsToday.filter { $0.kind == .focus }.reduce(0) { $0 + $1.focusedS } / 60
        if selectedTaskID == nil || !tasks.contains(where: { $0.taskID == selectedTaskID && $0.status.isOpen }) {
            selectedTaskID = (tasks.first { $0.status.isOpen && $0.priority == .high } ?? tasks.first { $0.status.isOpen })?.taskID
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    var filteredTasks: [TaskItem] { tasks(for: filter) }

    func tasks(for f: TaskFilter) -> [TaskItem] {
        switch f {
        case .all: return tasks
        case .done: return tasks.filter { $0.status == .done }
        case .later: return tasks.filter(\.isLater)
        case .focus: return tasks.filter { $0.status.isOpen && ($0.tags.contains { $0.lowercased() == "focus" } || $0.priority == .high) }
        }
    }

    func count(_ f: TaskFilter) -> Int { tasks(for: f).count }

    /// The first unfinished high-priority task gets the highlighted row.
    var highlightedID: String? { tasks.first { $0.status.isOpen && $0.priority == .high }?.taskID }

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
        if !skipSuggestion, let s = coordinator.suggestionBeforeStart(minutes: mins) {
            present(s)
            return
        }
        do {
            try coordinator.startFocus(task: t, minutes: mins)
            scheduleEndNotification()
        } catch { toast = UndoToast(text: "A session is already running", undo: {}) }
        publish()
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
        phase = coordinator.engine.phase
    }

    private func ended(_ r: SessionRecord) {
        lastEnded = r
        if let s = coordinator.sessionEnded(r) { present(s) }
        publish()
    }

    private func scheduleEndNotification() {
        guard let end = coordinator.engine.endDate, let a = coordinator.engine.active else { return }
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
        if let p = previous, p.prefix(7) != coordinator.today.prefix(7) { savePostcard(month: String(p.prefix(7))) }
        publish()
    }

    func savePostcard(month: String? = nil) {
        let m = month ?? String(coordinator.today.prefix(7))
        let islands = garden.islands.filter { island in
            island.items.contains { $0.day.hasPrefix(m) }
        }
        let view = PostcardView(month: m, islands: islands, garden: garden).environment(\.theme, .night)
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
