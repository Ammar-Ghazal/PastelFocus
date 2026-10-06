import Foundation

/// One day's totals, rebuilt from the logs.
public struct DailyRollup: Codable, Sendable, Equatable {
    public var day: String
    public var focusedS = 0
    public var completed = 0
    public var interrupted = 0
    public var breaks = 0
    public var nsdr = 0
    public var tasksDone = 0
    public var postponements = 0
    public var firstStart: Date?
    public var lastEnd: Date?
    public var focusedByCategory: [String: Int] = [:]

    public init(day: String) { self.day = day }

    /// A "good day" for the garden: at least 2 finished focus sessions.
    public var isGoodDay: Bool { completed >= 2 }
}

public enum Rollups {
    public static func build(sessions: [SessionRecord], events: [TaskEvent], calendar: DayCalendar) -> [String: DailyRollup] {
        var out: [String: DailyRollup] = [:]
        for s in sessions {
            let d = calendar.day(s.startedAt)
            var r = out[d] ?? DailyRollup(day: d)
            switch s.kind {
            case .focus:
                r.focusedS += s.focusedS
                if s.outcome == .completed { r.completed += 1 } else { r.interrupted += 1 }
                r.focusedByCategory[s.category ?? "none", default: 0] += s.focusedS
                r.firstStart = min(r.firstStart ?? s.startedAt, s.startedAt)
                r.lastEnd = max(r.lastEnd ?? s.endedAt, s.endedAt)
            case .nsdr: r.nsdr += 1; r.breaks += 1
            default: r.breaks += 1
            }
            out[d] = r
        }
        for e in events {
            let d = calendar.day(e.at)
            var r = out[d] ?? DailyRollup(day: d)
            if e.type == .completed { r.tasksDone += 1 }
            if e.type == .rescheduled { r.postponements += 1 }
            out[d] = r
        }
        return out
    }
}

/// The Markdown files PastelFocus writes for Hermes (and you) to read.
public enum Reports {
    static func minutes(_ s: Int) -> String {
        let m = s / 60
        return m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min"
    }

    public struct NowState {
        public var appRunning: Bool
        public var phase: FocusPhase
        public var taskTitle: String?
        public var taskID: String?
        public var kind: SessionKind?
        public var remainingS: Int
        public var plannedS: Int
        public var pauses: Int
        public init(appRunning: Bool, phase: FocusPhase, taskTitle: String? = nil, taskID: String? = nil,
                    kind: SessionKind? = nil, remainingS: Int = 0, plannedS: Int = 0, pauses: Int = 0) {
            self.appRunning = appRunning; self.phase = phase; self.taskTitle = taskTitle; self.taskID = taskID
            self.kind = kind; self.remainingS = remainingS; self.plannedS = plannedS; self.pauses = pauses
        }
    }

    public static func now(_ state: NowState, today: [TaskItem], rollup: DailyRollup?, updated: Date, calendar: DayCalendar) -> String {
        var lines = ["# Now", "", "_Written by PastelFocus. Updated \(calendar.day(updated)) \(calendar.timeString(updated))._", ""]
        if !state.appRunning {
            lines += ["**PastelFocus is not running.** Totals below are from the last time it ran.", ""]
        } else {
            switch state.phase {
            case .idle: lines += ["**Timer:** idle", ""]
            case .running, .paused:
                let what = state.taskTitle.map { "\"\($0)\" (🆔 \(state.taskID ?? "none"))" } ?? "Unassigned"
                lines += ["**Timer:** \(state.phase == .paused ? "paused" : "focusing") on \(what) — \(minutes(state.remainingS)) left of \(minutes(state.plannedS)), pauses \(state.pauses)", ""]
            case .resting:
                let kind = state.kind == .nsdr ? "NSDR" : state.kind == .longBreak ? "long rest" : "short rest"
                lines += ["**Timer:** \(kind), \(minutes(state.remainingS)) left", ""]
            }
        }
        let r = rollup ?? DailyRollup(day: calendar.day(updated))
        let done = today.filter { $0.status == .done }.count
        lines += ["## Today", "",
                  "- Tasks: \(done) of \(today.count) done",
                  "- Focused: \(minutes(r.focusedS)) in \(r.completed) finished and \(r.interrupted) interrupted sessions",
                  "- Breaks: \(r.breaks) (NSDR \(r.nsdr))", "",
                  "## Open tasks", ""]
        let open = today.filter { $0.status.isOpen }
        lines += open.isEmpty ? ["- none"] : open.map { t in
            var bits = ["- \(t.title)", "🆔 \(t.taskID ?? "?")"]
            if t.priority != .none { bits.append(t.priority.label.lowercased()) }
            if let e = t.estimateSessions { bits.append("\(t.actualSessions ?? 0)/\(e) sessions") }
            return bits.joined(separator: " · ")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Weekly or monthly summary.
    public static func stats(title: String, days: [String], rollups: [String: DailyRollup], sessions: [SessionRecord]) -> String {
        let rs = days.compactMap { rollups[$0] }
        let focused = rs.reduce(0) { $0 + $1.focusedS }
        let completed = rs.reduce(0) { $0 + $1.completed }
        let interrupted = rs.reduce(0) { $0 + $1.interrupted }
        let total = completed + interrupted
        var lines = ["# \(title)", "", "_Written by PastelFocus from the session and event logs._", "",
                     "| Measure | Value |", "| --- | --- |",
                     "| Focused time | \(minutes(focused)) |",
                     "| Focus sessions | \(total) (\(completed) finished, \(interrupted) interrupted) |",
                     "| Finish rate | \(total == 0 ? "—" : pct(Double(completed) / Double(total))) |",
                     "| Tasks done | \(rs.reduce(0) { $0 + $1.tasksDone }) |",
                     "| Postponements | \(rs.reduce(0) { $0 + $1.postponements }) |",
                     "| Breaks (NSDR) | \(rs.reduce(0) { $0 + $1.breaks }) (\(rs.reduce(0) { $0 + $1.nsdr })) |",
                     "| Good days (2+ finished sessions) | \(rs.filter(\.isGoodDay).count) of \(days.count) |", ""]
        var cats: [String: Int] = [:]
        for r in rs { for (k, v) in r.focusedByCategory { cats[k, default: 0] += v } }
        if !cats.isEmpty {
            lines += ["## By category", "", "| Category | Focused |", "| --- | --- |"]
            lines += cats.sorted { $0.value > $1.value }.map { "| \($0.key) | \(minutes($0.value)) |" }
            lines.append("")
        }
        lines += ["## By day", "", "| Day | Focused | Finished | Interrupted | Tasks done |", "| --- | --- | --- | --- | --- |"]
        for d in days {
            let r = rollups[d] ?? DailyRollup(day: d)
            lines.append("| \(d) | \(minutes(r.focusedS)) | \(r.completed) | \(r.interrupted) | \(r.tasksDone) |")
        }
        // `sessions` must already be limited to this period.
        let reasons = Dictionary(grouping: sessions.filter { $0.kind == .focus && $0.outcome == .stoppedEarly },
                                 by: { $0.stopReason ?? "no reason" })
        if !reasons.isEmpty {
            lines += ["", "## Stop reasons", ""]
            lines += reasons.sorted { $0.value.count > $1.value.count }.map { "- \($0.key): \($0.value.count)" }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func insights(_ list: [Insight], totalFocusSessions: Int, since: String?, updated: Date, calendar: DayCalendar) -> String {
        var lines = ["# Insights", "", "_Written by PastelFocus each night from your own logs. Each pattern needs at least 12 sessions on 7+ days and a clear gap from your baseline._", ""]
        if list.isEmpty {
            lines += ["**Still learning.** \(totalFocusSessions) focus sessions logged\(since.map { " since \($0)" } ?? ""). Most patterns need 2–4 weeks of sessions.", ""]
        }
        for i in list {
            lines += ["## \(i.title)", "", i.evidence, "",
                      "- kind: \(i.kind) · scope: \(i.scope) · sample: \(i.sampleN) · window: \(i.windowDays) days", ""]
        }
        lines.append("_Updated \(calendar.day(updated)) \(calendar.timeString(updated))._")
        return lines.joined(separator: "\n") + "\n"
    }
}
