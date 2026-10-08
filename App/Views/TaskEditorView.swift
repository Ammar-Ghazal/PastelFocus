import AppKit
import PastelFocusCore
import SwiftUI

/// One editor window per task, opened by double-clicking a Today row (or ⋯ → Edit…).
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

/// The whole task, editable: title, details, tags, priority, status, estimate, dates and notes.
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
    @State private var priority: Priority
    @State private var estimate: Int
    @State private var scheduled: String?
    @State private var due: String?
    @State private var start: String?
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
        _priority = State(initialValue: original.priority)
        _estimate = State(initialValue: original.estimateSessions ?? 0)
        _scheduled = State(initialValue: original.scheduled)
        _due = State(initialValue: original.due)
        _start = State(initialValue: original.start)
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
                    Stepper(value: $estimate, in: 0...40) {
                        LabeledContent("Estimate", value: estimate == 0 ? "None" : "\(estimate) session\(estimate == 1 ? "" : "s")")
                    }
                    LabeledContent("Sessions done", value: "\(original.actualSessions ?? 0)")
                }
                Section("Dates") {
                    DayField(label: "Scheduled", day: $scheduled, placeholder: noteDay.map { "From its note (\($0))" } ?? "Not set")
                    DayField(label: "Due", day: $due)
                    DayField(label: "Starts", day: $start)
                    if let c = original.created { LabeledContent("Created", value: c) }
                    if let c = original.completed { LabeledContent("Completed", value: c) }
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
        edited.priority = priority
        edited.estimateSessions = estimate == 0 ? nil : estimate
        edited.scheduled = scheduled
        edited.due = due
        edited.start = start
        edited.notes = notes.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if let e = model.saveEdit(original, edited) { error = e } else { close() }
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
