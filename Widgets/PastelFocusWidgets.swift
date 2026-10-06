import AppIntents
import PastelFocusCore
import SwiftUI
import WidgetKit

// MARK: Data

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func load() -> WidgetSnapshot {
        guard let dir = WidgetBridge.container else { return .empty }
        return WidgetBridge.read(from: dir)
    }

    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: .empty) }
    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) { completion(SnapshotEntry(date: .now, snapshot: load())) }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let s = load()
        // The app reloads timelines on every change; this is only a safety refresh.
        var refresh = Date().addingTimeInterval(15 * 60)
        if let end = s.timerEnd, end > .now { refresh = min(refresh, end.addingTimeInterval(2)) }
        completion(Timeline(entries: [SnapshotEntry(date: .now, snapshot: s)], policy: .after(refresh)))
    }
}

// MARK: Intents (run in the widget; they queue a command the app applies)

struct ToggleTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle task"
    @Parameter(title: "Task ID") var taskID: String
    init() {}
    init(taskID: String) { self.taskID = taskID }
    func perform() async throws -> some IntentResult {
        if let dir = WidgetBridge.container { try WidgetBridge.enqueue(WidgetCommand(action: .toggleTask, taskID: taskID, at: .now), in: dir) }
        return .result()
    }
}

struct TimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start or pause focus"
    @Parameter(title: "Action") var action: String
    init() {}
    init(action: WidgetCommand.Action) { self.action = action.rawValue }
    func perform() async throws -> some IntentResult {
        if let dir = WidgetBridge.container, let a = WidgetCommand.Action(rawValue: action) {
            try WidgetBridge.enqueue(WidgetCommand(action: a, taskID: nil, at: .now), in: dir)
        }
        return .result()
    }
}

// MARK: Style

private let navy = Color(red: 0.067, green: 0.094, blue: 0.153)
private let pink = Color(red: 0.965, green: 0.651, blue: 0.812)
private let pinkLight = Color(red: 1, green: 0.824, blue: 0.902)
private let textPrimary = Color(red: 0.961, green: 0.929, blue: 0.965)
private let textSecondary = Color(red: 0.667, green: 0.663, blue: 0.729)
private let coral = Color(red: 1, green: 0.51, blue: 0.569)
private let lavender = Color(red: 0.725, green: 0.718, blue: 1)

// MARK: Today widget

struct TodayWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        let s = entry.snapshot
        let rows = Array(s.tasks.prefix(family == .systemLarge || family == .systemExtraLarge ? 6 : 3))
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("✦ Today").font(.system(size: 17, weight: .bold)).foregroundStyle(pink)
                Spacer()
                Text("\(s.doneCount)/\(s.totalCount)").font(.system(size: 12, weight: .semibold)).foregroundStyle(textSecondary)
            }
            if rows.isEmpty {
                Text("No tasks planned yet").font(.system(size: 12)).foregroundStyle(textSecondary)
            }
            ForEach(rows, id: \.id) { r in
                Button(intent: ToggleTaskIntent(taskID: r.id)) {
                    HStack(spacing: 8) {
                        Image(systemName: r.done ? "checkmark.square.fill" : "square").foregroundStyle(r.done ? pinkLight : textSecondary)
                        Text(r.title).font(.system(size: 13, weight: .semibold)).strikethrough(r.done)
                            .foregroundStyle(r.done ? textSecondary : textPrimary).lineLimit(1)
                        Spacer()
                        if r.high, !r.done { Text("High").font(.system(size: 10, weight: .semibold)).foregroundStyle(coral) }
                        else if let t = r.tag { Text(t).font(.system(size: 10, weight: .semibold)).foregroundStyle(lavender) }
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            ProgressView(value: s.progress).tint(pink)
        }
        .containerBackground(navy, for: .widget)
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PastelFocusToday", provider: SnapshotProvider()) { TodayWidgetView(entry: $0) }
            .configurationDisplayName("Today")
            .description("Today's tasks from your daily note. Tap to tick.")
            .supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge])
    }
}

// MARK: Focus widget

struct FocusWidgetView: View {
    let entry: SnapshotEntry
    var body: some View {
        let s = entry.snapshot
        VStack(alignment: .leading, spacing: 6) {
            Text("◎ Focus").font(.system(size: 15, weight: .semibold)).foregroundStyle(pink)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let start = s.timerStart, s.phase == .running {
                        Text(start, style: .timer) // counts up by itself
                            .font(.system(size: 30, weight: .medium, design: .monospaced)).foregroundStyle(pinkLight)
                    } else if let elapsed = s.elapsedS {
                        Text(String(format: "%02d:%02d", elapsed / 60, elapsed % 60))
                            .font(.system(size: 30, weight: .medium, design: .monospaced)).foregroundStyle(pinkLight)
                    } else if let end = s.timerEnd, s.phase == .running || s.phase == .resting, end > entry.date {
                        Text(timerInterval: entry.date...end, countsDown: true)
                            .font(.system(size: 30, weight: .medium, design: .monospaced)).foregroundStyle(pinkLight)
                    } else {
                        Text(String(format: "%02d:%02d", s.remainingS / 60, s.remainingS % 60))
                            .font(.system(size: 30, weight: .medium, design: .monospaced)).foregroundStyle(pinkLight)
                    }
                    Text(s.phase == .paused ? "Paused" : s.timerTitle).font(.system(size: 12)).foregroundStyle(textSecondary).lineLimit(1)
                }
                Spacer()
                let action: WidgetCommand.Action = s.phase == .running ? .pauseFocus : s.phase == .paused ? .resumeFocus : .startFocus
                Button(intent: TimerIntent(action: action)) {
                    Image(systemName: s.phase == .running ? "pause.fill" : "play.fill").font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(red: 0.14, green: 0.13, blue: 0.2)).frame(width: 44, height: 44).background(Circle().fill(pink))
                }
                .buttonStyle(.plain)
            }
            Text("\(s.focusedMinutesToday) min focused today").font(.system(size: 11)).foregroundStyle(textSecondary)
        }
        .containerBackground(navy, for: .widget)
    }
}

struct FocusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PastelFocusTimer", provider: SnapshotProvider()) { FocusWidgetView(entry: $0) }
            .configurationDisplayName("Focus")
            .description("Start, pause and watch the focus timer.")
            .supportedFamilies([.systemMedium])
    }
}

// MARK: Progress and Next widgets

struct ProgressWidgetView: View {
    let entry: SnapshotEntry
    var body: some View {
        let s = entry.snapshot
        VStack(alignment: .leading, spacing: 6) {
            Text("PROGRESS").font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(pink)
            Text("\(Int((s.progress * 100).rounded()))%").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(textPrimary)
            ProgressView(value: s.progress).tint(pink)
            Text("\(s.doneCount) of \(s.totalCount) tasks · \(s.goodDays) good days").font(.system(size: 10)).foregroundStyle(textSecondary)
            if let n = s.nextTask {
                Text("Next: \(n.title)").font(.system(size: 11, weight: .semibold)).foregroundStyle(textPrimary).lineLimit(2)
            }
        }
        .containerBackground(navy, for: .widget)
    }
}

struct ProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PastelFocusProgress", provider: SnapshotProvider()) { ProgressWidgetView(entry: $0) }
            .configurationDisplayName("Progress")
            .description("Today's progress and the next task.")
            .supportedFamilies([.systemSmall])
    }
}

@main
struct PastelFocusWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        FocusWidget()
        ProgressWidget()
    }
}
