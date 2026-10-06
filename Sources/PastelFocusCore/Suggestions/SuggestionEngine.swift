import Foundation

/// The only moments a suggestion may appear. Never while a session is running.
public enum SuggestionMoment {
    case sessionStart(plannedMinutes: Int)
    /// `blocksToday` = focus sessions already finished or stopped today.
    case sessionEnd(blocksToday: Int)
    case planning(TaskItem)
}

public enum SuggestionAction: Equatable, Sendable {
    case useShorterSessions(minutes: Int)
    case takeBreak(kind: SessionKind, minutes: Int)
    case raiseEstimate(taskID: String, sessions: Int)
    case splitOrDrop(taskID: String)
}

public struct Suggestion: Equatable, Sendable, Identifiable {
    public var id: String
    public var kind: String
    public var title: String
    /// Evidence sentence with real numbers, shown behind "Why?".
    public var why: String
    public var action: SuggestionAction
}

public struct SuggestionBudget: Sendable {
    public var maxPerDay = 3
    public var minGapS: TimeInterval = 90 * 60
    public var perKindCooldownDays = 3
    public var pauseAfterDismissalsDays = 14
    public init() {}
}

/// Local, deterministic rules that turn insights into rare, explainable suggestions.
public final class SuggestionEngine {
    let calendar: DayCalendar
    public var budget = SuggestionBudget()
    public private(set) var history: [SuggestionRecord]

    public init(calendar: DayCalendar, history: [SuggestionRecord]) {
        self.calendar = calendar
        self.history = history.sorted { $0.at < $1.at }
    }

    public func evaluate(_ moment: SuggestionMoment, insights: [Insight], now: Date, sessionRunning: Bool) -> Suggestion? {
        guard !sessionRunning, let candidate = candidate(moment, insights: insights), allowed(kind: candidate.kind, now: now) else { return nil }
        return candidate
    }

    func candidate(_ moment: SuggestionMoment, insights: [Insight]) -> Suggestion? {
        switch moment {
        case .sessionStart(let planned):
            guard let span = insights.first(where: { $0.kind == "focus_span" }),
                  Double(planned) > 0, (Double(planned) - span.value) / Double(planned) >= 0.15 else { return nil }
            let minutes = max(15, Int(span.value / 5) * 5)
            return Suggestion(id: Self.newID(), kind: "shorter_sessions", title: "Try \(minutes)-minute sessions today?",
                              why: span.evidence, action: .useShorterSessions(minutes: minutes))
        case .sessionEnd(let blocks):
            guard let fat = insights.first(where: { $0.kind == "fatigue" }),
                  let n = Int(fat.scope.replacingOccurrences(of: "session#", with: "").replacingOccurrences(of: "+", with: "")),
                  blocks + 1 >= n else { return nil }
            let nsdr = insights.first { $0.kind == "nsdr" }
            let nsdrHelps = nsdr.map { ($0.baseline ?? 0) > $0.value } ?? true
            var why = fat.evidence
            if let nsdr { why += " " + nsdr.evidence }
            if nsdrHelps {
                return Suggestion(id: Self.newID(), kind: "break_nsdr", title: "Your focus usually dips about now. Consider a 15-minute NSDR break.",
                                  why: why, action: .takeBreak(kind: .nsdr, minutes: 15))
            }
            return Suggestion(id: Self.newID(), kind: "break_long", title: "Your focus usually dips about now. A longer break or a walk may help.",
                              why: why, action: .takeBreak(kind: .longBreak, minutes: 20))
        case .planning(let task):
            guard let id = task.taskID else { return nil }
            if let p = insights.first(where: { $0.kind == "postponed" && $0.scope == "task:\(id)" }) {
                return Suggestion(id: Self.newID(), kind: "split_or_drop", title: "Split \"\(task.title)\" into a smaller first step, or drop it?",
                                  why: p.evidence, action: .splitOrDrop(taskID: id))
            }
            if let cat = task.category, let est = task.estimateSessions,
               let e = insights.first(where: { $0.kind == "estimate" && $0.scope == "category:\(cat)" && $0.value >= 1.5 }) {
                let sessions = Int((Double(est) * e.value).rounded(.up))
                guard sessions > est else { return nil }
                return Suggestion(id: Self.newID(), kind: "raise_estimate", title: "Plan \(sessions) sessions for \"\(task.title)\" instead of \(est)?",
                                  why: e.evidence, action: .raiseEstimate(taskID: id, sessions: sessions))
            }
            return nil
        }
    }

    /// The interruption budget from the spec.
    public func allowed(kind: String, now: Date) -> Bool {
        let shown = history.filter { $0.response == .shown }
        if history.contains(where: { $0.kind == kind && $0.response == .muted }) { return false }
        let today = calendar.day(now)
        if shown.filter({ calendar.day($0.at) == today }).count >= budget.maxPerDay { return false }
        if let last = shown.last, now.timeIntervalSince(last.at) < budget.minGapS { return false }
        if let lastKind = shown.last(where: { $0.kind == kind }),
           now.timeIntervalSince(lastKind.at) < Double(budget.perKindCooldownDays) * 86_400 { return false }
        let answers = history.filter { $0.kind == kind && $0.response != .shown }
        if answers.count >= 2, answers.suffix(2).allSatisfy({ $0.response == .dismissed }),
           now.timeIntervalSince(answers.last!.at) < Double(budget.pauseAfterDismissalsDays) * 86_400 { return false }
        return true
    }

    /// Records that a suggestion was shown or answered. Persist the returned record.
    @discardableResult
    public func record(_ s: Suggestion, _ response: SuggestionResponse, at: Date) -> SuggestionRecord {
        let r = SuggestionRecord(id: s.id, kind: s.kind, at: at, response: response, why: response == .shown ? s.why : nil)
        history.append(r)
        return r
    }

    static func newID() -> String { "g" + UUID().uuidString.prefix(6).lowercased() }
}
