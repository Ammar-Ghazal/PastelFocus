import PastelFocusCore
import SwiftUI

struct TodayView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.theme) var theme
    @Environment(\.snapshotMode) var snapshot
    @State private var adding = false
    @State private var newText = ""
    @FocusState private var fieldFocused: Bool
    @State private var grabberHover = false

    static let defaultHeight: CGFloat = 690
    /// The panel's height can be dragged within this range (the width is fixed); the list scrolls.
    static let heightRange: ClosedRange<CGFloat> = 360...900

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            pills
            if adding { addField }
            list
            Divider().overlay(theme.border)
            footer
        }
        .padding(PanelStyle.padding)
        .frame(width: 560, alignment: .topLeading)
        .frame(minHeight: Self.heightRange.lowerBound, maxHeight: .infinity, alignment: .top)
        .background(GlassBackground(sceneOpacity: 0.28))
        .overlay(alignment: .bottom) { ToastView().padding(.bottom, 12) }
        .overlay(alignment: .bottom) { if !snapshot { resizeGrabber } }
    }

    /// Drag to change the panel's height. A faint bar that brightens on hover.
    private var resizeGrabber: some View {
        ZStack {
            Capsule().fill(theme.textTertiary.opacity(grabberHover ? 0.8 : 0.3)).frame(width: 40, height: 4)
            PanelResizeHandle()
        }
        .frame(maxWidth: .infinity).frame(height: 12)
        .onHover { grabberHover = $0 }
        .help("Drag to resize")
    }

    private var header: some View {
        HStack(alignment: .top) {
            PanelTitle("Today")
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(Date.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(theme.textSecondary)
                if model.problemsCount > 0 {
                    Label("\(model.problemsCount) unreadable line\(model.problemsCount == 1 ? "" : "s")", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11)).foregroundStyle(theme.tagLater)
                        .help("See PastelFocus/Problems.md in your vault")
                }
            }
        }
    }

    private var pills: some View {
        HStack(spacing: 8) {
            ForEach(TaskFilter.allCases, id: \.self) { f in
                let active = model.filter == f
                Button { model.filter = f } label: {
                    HStack(spacing: 6) {
                        Text(f.rawValue)
                        Text("\(model.count(f))").opacity(0.8)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 16).frame(height: 34)
                    .foregroundStyle(active ? theme.onAccent : theme.textSecondary)
                    .background(Capsule().fill(active ? AnyShapeStyle(theme.accent) : AnyShapeStyle(theme.elevated)))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button { withAnimation(.easeOut(duration: 0.2)) { adding.toggle(); fieldFocused = adding } } label: {
                Image(systemName: adding ? "xmark" : "plus").font(.system(size: 20, weight: .semibold)).foregroundStyle(theme.onAccent)
                    .frame(width: 48, height: 48).background(RoundedRectangle(cornerRadius: 9).fill(theme.accent))
            }
            .buttonStyle(PressableStyle())
            .help("Add a task (Enter to save, Esc to cancel)")
        }
    }

    private var addField: some View {
        TextField("New task — add #tag, ⏫ or [est:: 2] if you like", text: $newText)
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .foregroundStyle(theme.textPrimary)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(theme.elevated))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.borderActive))
            .focused($fieldFocused)
            .onSubmit { model.add(newText); newText = ""; adding = false }
            .onExitCommand { newText = ""; adding = false }
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder private var list: some View {
        if model.tasks.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                SpriteView(rows: Sprite.catMascot, px: 4)
                Text("Hermes hasn't planned today yet").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.textPrimary)
                Button("Create empty note") { model.createTodayNote() }
                    .buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.onAccent)
                    .padding(.horizontal, 14).padding(.vertical, 8).background(Capsule().fill(theme.accent))
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if snapshot {
            VStack(spacing: 4) {
                ForEach(model.filteredTasks.prefix(7)) { t in TaskRow(task: t, highlighted: t.taskID == model.highlightedID) }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 0, maxHeight: .infinity, alignment: .top).clipped() // shrinks like the scroll view
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 4) {
                    ForEach(model.filteredTasks) { t in
                        TaskRow(task: t, highlighted: t.taskID == model.highlightedID)
                            .transition(.asymmetric(insertion: .offset(y: -6).combined(with: .opacity), removal: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.2), value: model.filteredTasks.map(\.id))
            }
        }
    }

    private var footer: some View {
        let done = model.tasks.filter { $0.status == .done }.count, total = model.tasks.count
        let fraction = total == 0 ? 0 : Double(done) / Double(total)
        return HStack(alignment: .center, spacing: 14) {
            SpriteView(rows: Sprite.catMascot, px: 4)
            VStack(alignment: .leading, spacing: 6) {
                PixelLabel(text: "Daily Progress", size: 13)
                Text("\(done) of \(total) completed").font(.system(size: 12)).foregroundStyle(theme.textSecondary)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(theme.track)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(theme.accent)
                            .frame(width: g.size.width * fraction)
                            .animation(.spring(response: 0.45), value: fraction)
                    }
                }
                .frame(height: 8)
            }
            Text("\(Int((fraction * 100).rounded()))%").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(theme.textPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.todayFocusedMin) min").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.textPrimary)
                Text("focused today").font(.system(size: 11)).foregroundStyle(theme.textSecondary)
            }
            .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(theme.elevated.opacity(0.7)))
        }
    }
}

struct TaskRow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.theme) var theme
    @Environment(\.plantArt) var plantArt
    @Environment(\.snapshotMode) var snapshot
    let task: TaskItem
    let highlighted: Bool
    @State private var hover = false

    var done: Bool { task.status == .done }

    var body: some View {
        HStack(spacing: 14) {
            Checkbox(checked: done) { model.toggle(task) }.padding(-6) // bigger target, same layout
            SpriteView(rows: plantArt.sprite(forTag: task.category), px: 2).opacity(done ? 0.5 : 1) // the plant its first tag grows
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title).font(.system(size: 15, weight: .semibold))
                    .strikethrough(done, color: theme.textTertiary)
                    .foregroundStyle(done ? theme.textTertiary : theme.textPrimary)
                    .lineLimit(1)
                    .onTapGesture { model.openInObsidian(task) }
                HStack(spacing: 6) {
                    if let s = task.subtitle { Text(s).lineLimit(1) }
                    if let e = task.estimateSessions { Text("· \(task.actualSessions ?? 0)/\(e) sessions") }
                }
                .font(.system(size: 12)).foregroundStyle(theme.textSecondary)
            }
            .opacity(done ? 0.58 : 1)
            Spacer()
            if task.priority >= .high, !done { TagChip(text: task.priority.label) }
            else if let c = task.isLater ? "Later" : task.category?.capitalized { TagChip(text: c) }
            // Shown on hover (always on the highlighted row). The slot is kept when hidden so chips don't shift.
            let showPlay = !done && (hover || highlighted)
            Button { model.startFocus(on: task) } label: {
                Image(systemName: "play.fill").font(.system(size: 12)).foregroundStyle(theme.accent).frame(width: 28, height: 28)
            }
            .buttonStyle(.plain).help("Start focus")
            .opacity(showPlay ? 1 : 0).allowsHitTesting(showPlay)
            if snapshot {
                Image(systemName: "ellipsis").foregroundStyle(theme.textSecondary).frame(width: 28)
            } else {
                Menu { actions } label: { Image(systemName: "ellipsis").foregroundStyle(theme.textSecondary) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28)
            }
        }
        .padding(.horizontal, 14).frame(height: 60)
        .background(RoundedRectangle(cornerRadius: 10).fill(highlighted && !done ? theme.highlight : (hover ? Color.white.opacity(0.035) : .clear)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(highlighted && !done ? theme.accent.opacity(0.2) : .clear))
        .onHover { h in withAnimation(.easeOut(duration: 0.14)) { hover = h } }
        .contextMenu { actions }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(task.title), \(done ? "done" : "not done")\(task.priority == .none ? "" : ", \(task.priority.label.lowercased()) priority")")
    }
}

extension TaskRow {
    /// The ⋯ menu, also shown on right-click.
    @ViewBuilder var actions: some View {
        Button("Start focus") { model.startFocus(on: task) }.disabled(done)
        Picker("Priority", selection: Binding(get: { task.priority }, set: { model.setPriority(task, $0) })) {
            ForEach(Priority.levels, id: \.self) { Text($0.label).tag($0) }
            Text("None").tag(Priority.none)
        }
        Button("Move to Later") { model.moveToLater(task) }.disabled(done || task.isLater)
        Button("Open in Obsidian") { model.openInObsidian(task) }
        Divider()
        Button("Delete", role: .destructive) { model.delete(task) }
    }
}

struct Checkbox: View {
    @Environment(\.theme) var theme
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    let checked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 5).strokeBorder(theme.textTertiary, lineWidth: 1.5)
                    .background(RoundedRectangle(cornerRadius: 5).fill(checked ? theme.accent : .clear))
                if checked { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(theme.onAccent) }
            }
            .frame(width: 20, height: 20)
            .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.7), value: checked)
            // An unchecked box is only an outline with a clear fill, so without this just the 1.5 pt
            // border took clicks. Pad the target too: a 20 pt box is small to hit.
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(checked ? "Mark not done" : "Mark done")
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.97 : 1).animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ToastView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.theme) var theme
    var body: some View {
        if let t = model.toast {
            HStack(spacing: 12) {
                Text(t.text).font(.system(size: 12)).foregroundStyle(theme.textPrimary).lineLimit(1)
                Button("Undo") { t.undo(); model.toast = nil }.buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.accent)
                Button { model.toast = nil } label: { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain).foregroundStyle(theme.textSecondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(theme.elevated))
            .overlay(Capsule().strokeBorder(theme.border))
            .task(id: t.id) { try? await Task.sleep(for: .seconds(10)); if model.toast?.id == t.id { model.toast = nil } }
        }
    }
}
