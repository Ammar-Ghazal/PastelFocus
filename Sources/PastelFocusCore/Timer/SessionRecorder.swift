import Foundation

/// Writes a finished session everywhere it belongs: the sessions log, the daily note's
/// focus log, and the task's `[sessions:: n]` count.
public final class SessionRecorder {
    public let config: VaultConfig
    public let calendar: DayCalendar
    public let store: TaskStore
    public let log: JSONLLog<SessionRecord>

    public init(config: VaultConfig, calendar: DayCalendar, store: TaskStore) {
        self.config = config
        self.calendar = calendar
        self.store = store
        self.log = JSONLLog(directory: config.logsDir, prefix: "sessions", calendar: calendar)
    }

    public func record(_ s: SessionRecord) throws {
        try log.append(s, at: s.startedAt)
        guard s.kind == .focus else { return }
        let day = calendar.day(s.startedAt)
        try SafeFile.appendToSection("## Focus log", line: Self.focusLogLine(s, calendar: calendar),
                                     in: config.dailyNote(day), fileHeader: DailyNote.header(day: day, calendar: calendar))
        if let id = s.taskId, s.outcome == .completed, store.find(id) != nil {
            let n = log.readAll().filter { $0.kind == .focus && $0.taskId == id && $0.outcome == .completed }.count
            try store.setActualSessions(id, n)
        }
    }

    /// `- 09:02–09:27 · 🆔 k3m9 · LeetCode · 25/25 min · completed · pauses 0`
    public static func focusLogLine(_ s: SessionRecord, calendar: DayCalendar) -> String {
        let span = "\(calendar.timeString(s.startedAt))–\(calendar.timeString(s.endedAt))"
        let title = s.taskTitle.map { String($0.prefix(40)) } ?? "Unassigned"
        let done = Int((Double(s.focusedS) / 60).rounded())
        let minutes = s.isStopwatch ? "\(done) min (stopwatch)" : "\(done)/\(s.plannedS / 60) min"
        var outcome: String
        switch s.outcome {
        case .completed: outcome = "completed"
        case .stoppedEarly: outcome = "stopped early"
        case .pausedOut: outcome = "paused out"
        case .sleepInterrupted: outcome = "sleep interrupted"
        case .skipped: outcome = "skipped"
        }
        // The note shows a short label; the sessions log keeps the full text.
        if let r = s.stopReason, s.outcome == .stoppedEarly, !r.isEmpty { outcome += " (\(StopReasons.shorten(r)))" }
        let pauseMin = s.pauses.reduce(0) { $0 + $1.durS } / 60
        let pauses = s.pauses.isEmpty ? "pauses 0" : "pauses \(s.pauses.count) (\(pauseMin) min)"
        return "- \(span) · 🆔 \(s.taskId ?? "none") · \(title) · \(minutes) · \(outcome) · \(pauses)"
    }
}
