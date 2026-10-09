import AppKit
import PastelFocusCore
import SwiftUI

/// One editor window per task, opened by a Today row's pencil, a double-click or right-click → Edit….
@MainActor
final class TaskEditorWindows {
    private var windows: [String: NSWindow] = [:]
    private var observers: [String: NSObjectProtocol] = [:]

    func open(_ task: TaskItem, model: AppModel) {
        guard let id = task.taskID else { return }
        NSApp.activate()
        if let w = windows[id] { w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 640),
                         styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "Edit Task"
        w.isReleasedWhenClosed = false
        w.level = .floating // above the desktop panels, even when they float
        w.contentMinSize = CGSize(width: 420, height: 480)
        w.contentView = NSHostingView(rootView: Themed { TaskEditorView(original: task) { [weak w] in w?.close() } }.environmentObject(model))
        w.center()
        observers[id] = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.windows[id] = nil
                if let o = self?.observers.removeValue(forKey: id) { NotificationCenter.default.removeObserver(o) }
            }
        }
        windows[id] = w
        w.makeKeyAndOrderFront(nil)
    }
}

/// The whole task, editable: title, details, tags, priority, status, dates, repeat and notes, plus
/// the time spent on it (read-only: it comes from the focus sessions).
/// Saving writes only what was changed here, so edits Hermes makes meanwhile are kept.
struct TaskEditorView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.plantArt) var plantArt
    @Environment(\.theme) var theme
    let original: TaskItem
    let close: () -> Void

    @State private var title: String
    @State private var details: String
    @State private var tags: [String]
    @State private var status: TaskStatus
    @State private var progress: Int?
    @State private var priority: Priority
    @State private var scheduled: String?
    @State private var due: String?
    @State private var start: String?
    @State private var recurrence: String
    @State private var startTime: String?
    @State private var duration: Int?
    @State private var notes: String
    @State private var newTag = ""
    @State private var error: String?

    init(original: TaskItem, close: @escaping () -> Void) {
        self.original = original
        self.close = close
        _title = State(initialValue: original.title)
        _details = State(initialValue: original.subtitle ?? "")
        _tags = State(initialValue: original.tags)
        _status = State(initialValue: original.status)
        _progress = State(initialValue: original.progress)
        _priority = State(initialValue: original.priority)
        _scheduled = State(initialValue: original.scheduled)
        _due = State(initialValue: original.due)
        _start = State(initialValue: original.start)
        _recurrence = State(initialValue: original.recurrence ?? "")
        _startTime = State(initialValue: original.startTime)
        _duration = State(initialValue: original.durationMinutes)
        _notes = State(initialValue: original.notes.joined(separator: "\n"))
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Title", text: $title, prompt: Text("Title"), axis: .vertical)
                        .font(.system(size: 15, weight: .semibold)).labelsHidden()
                    TextField("Details", text: $details, prompt: Text("Details (optional)"), axis: .vertical).labelsHidden()
                }
                Section {
                    tagEditor
                } header: {
                    Text("Tags")
                } footer: {
                    Text("The first tag decides the plant. Click a tag to make it first.").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Picker("Priority", selection: $priority) {
                        ForEach(Priority.levels, id: \.self) { Text($0.label).tag($0) }
                        Text("None").tag(Priority.none)
                    }
                    .pickerStyle(.segmented)
                    Picker("Status", selection: $status) {
                        Text("To do").tag(TaskStatus.todo)
                        Text("In progress").tag(TaskStatus.inProgress)
                        Text("Done").tag(TaskStatus.done)
                        Text("Cancelled").tag(TaskStatus.cancelled)
                    }
                    LabeledContent("Progress") {
                        HStack(spacing: 8) {
                            if let p = progress {
                                Slider(value: Binding(get: { Double(p) }, set: { progress = Int($0) }), in: 0...100, step: 5)
                                    .frame(maxWidth: 160).accessibilityLabel("Progress")
                                Text("\(p)%").monospacedDigit().frame(width: 38, alignment: .trailing)
                            } else {
                                Text("Not reported").foregroundStyle(.secondary)
                            }
                            Toggle("Progress", isOn: Binding(get: { progress != nil }, set: { progress = $0 ? (progress ?? 50) : nil }))
                                .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        }
                    }
                    .help("How much of the whole task is done; 100% completes it")
                    LabeledContent("Time spent", value: (original.spentMinutes ?? 0) > 0 ? GoodDay.label(original.spentMinutes!) : "None yet")
                        .help("Logged from focus sessions on this task")
                }
                Section {
                    DayField(label: "Scheduled", day: $scheduled, placeholder: noteDay.map { "From its note (\($0))" } ?? "Not set")
                    DayField(label: "Due", day: $due)
                    DayField(label: "Starts", day: $start)
                    TimeField(time: $startTime)
                    Picker("Length", selection: $duration) {
                        Text("None").tag(Int?.none)
                        ForEach(Self.lengths(including: duration), id: \.self) { m in Text(GoodDay.label(m)).tag(Int?.some(m)) }
                    }
                    RepeatField(text: $recurrence)
                    if let c = original.created { LabeledContent("Created", value: c) }
                    if let c = original.completed { LabeledContent("Completed", value: c) }
                } header: {
                    Text("Schedule")
                } footer: {
                    Text("A repeating task is one line: ticking it off adds the next one on its day. Today shows only its current day.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    TextEditor(text: $notes).font(.system(size: 13)).frame(minHeight: 70)
                } header: {
                    Text("Notes")
                } footer: {
                    Text("One note per line; saved as bullets under the task in \(original.file).").font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            Divider()
            buttons.padding(14).background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 420, minHeight: 480)
        .tint(theme.accent)
    }

    // MARK: Tags

    private var tagEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SpriteView(rows: plantArt.sprite(forTag: plantTag), px: 3)
                FlowLayout(spacing: 6) {
                    ForEach(Array(tags.enumerated()), id: \.offset) { i, tag in chip(tag, first: i == 0) }
                    if tags.isEmpty { Text("No tags").foregroundStyle(.secondary) }
                }
            }
            HStack {
                TextField("Add a tag", text: $newTag, prompt: Text("Add a tag")).labelsHidden()
                    .textFieldStyle(.roundedBorder).onSubmit { addTag(newTag) }
                let unused = model.tags.tags.map(\.name).filter { n in !tags.contains { $0.lowercased() == n } }
                Menu("Existing") {
                    ForEach(unused, id: \.self) { n in Button("#\(n)") { addTag(n) } }
                    if !tags.contains(where: { $0.lowercased() == "later" }) {
                        Divider()
                        Button("#later (move to Later)") { addTag("later") }
                    }
                }
                .fixedSize()
                .disabled(unused.isEmpty && tags.contains { $0.lowercased() == "later" })
            }
        }
    }

    /// The tag that picks the plant: the first one, skipping #later (as `TaskItem.category` does).
    private var plantTag: String? {
        tags.map { $0.lowercased() }.first { !TagRegistry.reserved.contains($0) }
    }

    private func chip(_ tag: String, first: Bool) -> some View {
        HStack(spacing: 4) {
            Text("#\(tag)").font(.system(size: 12, weight: first ? .semibold : .regular))
            Button { tags.removeAll { $0 == tag } } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove #\(tag)")
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(first ? theme.accent.opacity(0.22) : Color.secondary.opacity(0.14)))
        .contentShape(Capsule())
        .onTapGesture { if let i = tags.firstIndex(of: tag) { tags.insert(tags.remove(at: i), at: 0) } }
        .help(first ? "The first tag decides the plant" : "Click to make this the first tag")
    }

    private func addTag(_ raw: String) {
        let n = TagRegistry.normalize(raw)
        guard !n.isEmpty else { return }
        guard TagRegistry.isValid(n) else { error = TagError.invalidName.description; return }
        if !tags.contains(where: { $0.lowercased() == n }) { tags.append(n) }
        newTag = ""
        error = nil
    }

    // MARK: Saving

    private var noteDay: String? { model.coordinator.config.noteDay(forRelative: original.file) }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button("Delete", role: .destructive) { model.delete(original); close() }
            Button("Open in Obsidian") { model.openInObsidian(original) }
            if let error { Text(error).font(.caption).foregroundStyle(.red).lineLimit(2) }
            Spacer()
            Button("Cancel", action: close).keyboardShortcut(.cancelAction)
            Button("Save", action: save).keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty && tags.isEmpty)
        }
    }

    private func save() {
        if !newTag.isEmpty { addTag(newTag) } // typed but not yet added
        var edited = original
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines), d = details.trimmingCharacters(in: .whitespacesAndNewlines)
        if t != original.title || d != (original.subtitle ?? "") || tags != original.tags {
            // Rebuilt as "Title — details #tags"; left untouched (tags in place) when none of these changed.
            edited.description = ([d.isEmpty ? t : "\(t) — \(d)"] + tags.map { "#\($0)" })
                .joined(separator: " ").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        }
        edited.status = status
        edited.progress = progress
        edited.priority = priority
        edited.scheduled = scheduled
        edited.due = due
        edited.start = start
        let rule = recurrence.replacingOccurrences(of: "🔁", with: "").trimmingCharacters(in: .whitespaces)
        guard rule.isEmpty || Recurrence(rule) != nil else {
            error = "Repeats takes words like \"every day\", \"every weekday\" or \"every 2 weeks on Monday\"."
            return
        }
        edited.recurrence = rule.isEmpty ? nil : (Recurrence(rule)?.text ?? rule)
        edited.startTime = startTime
        edited.durationMinutes = duration
        edited.notes = notes.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if let e = model.saveEdit(original, edited) { error = e } else { close() }
    }
}

extension TaskEditorView {
    /// Lengths offered in the menu, plus the task's own if it's something else.
    static func lengths(including m: Int?) -> [Int] {
        let base = [15, 25, 30, 45, 60, 90, 120, 180, 240]
        return m.map { base.contains($0) ? base : (base + [$0]).sorted() } ?? base
    }
}

/// An optional time of day ("HH:MM").
private struct TimeField: View {
    @Binding var time: String?

    var body: some View {
        LabeledContent("Time") {
            HStack(spacing: 10) {
                if let t = time, let m = TaskTime.minutes(t) {
                    DatePicker("Time", selection: Binding(get: { Self.date(m) }, set: { time = Self.string($0) }), displayedComponents: .hourAndMinute)
                        .labelsHidden().datePickerStyle(.field)
                        .environment(\.timeZone, Self.utc.timeZone)
                } else {
                    Text("Any time").foregroundStyle(.secondary)
                }
                Toggle("Time", isOn: Binding(get: { time != nil }, set: { time = $0 ? (time ?? "09:00") : nil }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
        }
    }

    // A fixed reference day in UTC, so the picker shows the stored clock time unchanged.
    static var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    static func date(_ minutes: Int) -> Date { Date(timeIntervalSinceReferenceDate: TimeInterval(minutes * 60)) }
    static func string(_ d: Date) -> String {
        let c = utc.dateComponents([.hour, .minute], from: d)
        return TaskTime.string((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }
}

/// The repeat rule: never, the common choices, weekly or biweekly on chosen days, or your own words.
private struct RepeatField: View {
    @Binding var text: String

    enum Choice: String, CaseIterable, Identifiable {
        case never, daily, weekdays, weekends, weekly, biweekly, monthly, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .never: return "Never"
            case .daily: return "Every day"
            case .weekdays: return "Every weekday (Mon–Fri)"
            case .weekends: return "Every weekend (Sat, Sun)"
            case .weekly: return "Every week on…"
            case .biweekly: return "Every 2 weeks on…"
            case .monthly: return "Every month"
            case .custom: return "Custom…"
            }
        }
    }

    private var rule: Recurrence? { Recurrence(text) }

    private var choice: Choice {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return .never }
        guard let r = rule, !r.whenDone else { return .custom }
        switch (r.unit, r.interval) {
        case (.day, 1): return .daily
        case (.week, 1) where r.weekdays == [1, 2, 3, 4, 5]: return .weekdays
        case (.week, 1) where r.weekdays == [6, 7]: return .weekends
        case (.week, 1): return .weekly
        case (.week, 2): return .biweekly
        case (.month, 1): return .monthly
        default: return .custom
        }
    }

    var body: some View {
        Picker("Repeats", selection: Binding(get: { choice }, set: set)) {
            ForEach(Choice.allCases) { Text($0.label).tag($0) }
        }
        if choice == .weekly || choice == .biweekly {
            LabeledContent("On") {
                HStack(spacing: 4) {
                    ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { i, letter in
                        let day = i + 1
                        let on = rule?.weekdays.contains(day) ?? false
                        Button { toggle(day) } label: {
                            Text(letter).font(.system(size: 12, weight: on ? .bold : .regular))
                                .foregroundStyle(on ? Color.white : Color.primary)
                                .frame(width: 26, height: 24)
                                .background(RoundedRectangle(cornerRadius: 6).fill(on ? Color.accentColor : Color.secondary.opacity(0.18)))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                            .accessibilityLabel(Calendar.current.weekdaySymbols[day % 7])
                            .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
        }
        if choice == .custom {
            TextField("Rule", text: $text, prompt: Text("e.g. every 3 days, every month when done"))
                .foregroundStyle(text.isEmpty || rule != nil ? Color.primary : Color.red)
        }
    }

    private func set(_ c: Choice) {
        switch c {
        case .never: text = ""
        case .daily: text = "every day"
        case .weekdays: text = "every weekday"
        case .weekends: text = "every weekend"
        case .weekly, .biweekly:
            // Keep the chosen days when switching between weekly and biweekly; otherwise start on Monday.
            let keep = choice == .weekly || choice == .biweekly
            let days = keep ? (rule?.weekdays ?? []) : []
            text = Recurrence(interval: c == .weekly ? 1 : 2, unit: .week, weekdays: days.isEmpty ? [1] : days).text
        case .monthly: text = "every month"
        case .custom: if rule == nil && text.isEmpty { text = "every 3 days" }
        }
    }

    private func toggle(_ day: Int) {
        guard var r = rule else { return }
        if r.weekdays.contains(day) { if r.weekdays.count > 1 { r.weekdays.remove(day) } } else { r.weekdays.insert(day) }
        text = r.text
    }
}

/// An optional day (YYYY-MM-DD) with a date picker, in the vault's day calendar.
private struct DayField: View {
    @EnvironmentObject var model: AppModel
    let label: String
    @Binding var day: String?
    var placeholder = "Not set"

    var body: some View {
        let cal = model.coordinator.calendar
        LabeledContent(label) {
            HStack(spacing: 10) {
                if let d = day, let date = cal.startOfDay(d) {
                    DatePicker(label, selection: Binding(get: { date }, set: { day = cal.day($0) }), displayedComponents: .date)
                        .labelsHidden().datePickerStyle(.field)
                        .environment(\.timeZone, cal.timeZone)
                } else {
                    Text(placeholder).foregroundStyle(.secondary)
                }
                Toggle(label, isOn: Binding(get: { day != nil }, set: { day = $0 ? (day ?? cal.day(Date())) : nil }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
        }
    }
}
