import Foundation

public enum SessionKind: String, Codable, Sendable {
    case focus
    case shortBreak = "short_break"
    case longBreak = "long_break"
    case nsdr

    public var isBreak: Bool { self != .focus }
}

public enum SessionOutcome: String, Codable, Sendable {
    case completed
    case stoppedEarly = "stopped_early"
    case pausedOut = "paused_out"
    case sleepInterrupted = "sleep_interrupted"
    case skipped
    /// Handed over to another task mid-session; the timer carried on in a new session.
    case switched

    /// Anything other than finishing counts as an interruption for focus analytics, except moving
    /// to another task, which carries the session on rather than breaking it.
    public var isInterrupted: Bool { self != .completed && self != .switched }
}

public struct PauseRecord: Codable, Sendable, Equatable {
    /// Seconds of focus elapsed when the pause began.
    public var atS: Int
    public var durS: Int
    public init(atS: Int, durS: Int) { self.atS = atS; self.durS = durS }
}

/// One line of `PastelFocus/Logs/sessions-YYYY-MM.jsonl`.
public struct SessionRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: SessionKind
    public var taskId: String?
    public var taskTitle: String?
    public var category: String?
    public var preset: String
    public var plannedS: Int
    public var startedAt: Date
    public var endedAt: Date
    public var tz: String
    public var focusedS: Int
    public var outcome: SessionOutcome
    public var stopReason: String?
    public var pauses: [PauseRecord]
    public var rating: Int?

    public init(id: String, kind: SessionKind, taskId: String?, taskTitle: String?, category: String?,
                preset: String, plannedS: Int, startedAt: Date, endedAt: Date, tz: String,
                focusedS: Int, outcome: SessionOutcome, stopReason: String? = nil,
                pauses: [PauseRecord] = [], rating: Int? = nil) {
        self.id = id; self.kind = kind; self.taskId = taskId; self.taskTitle = taskTitle
        self.category = category; self.preset = preset; self.plannedS = plannedS
        self.startedAt = startedAt; self.endedAt = endedAt; self.tz = tz; self.focusedS = focusedS
        self.outcome = outcome; self.stopReason = stopReason; self.pauses = pauses; self.rating = rating
    }

    public var isStopwatch: Bool { preset == "stopwatch" }

    /// Seconds of focus before the first pause or stop; nil when the session ran clean to the end.
    public var secondsToFirstInterruption: Int? {
        if let p = pauses.first { return p.atS }
        return outcome.isInterrupted ? focusedS : nil
    }
}

public enum TaskEventType: String, Codable, Sendable {
    case created, edited, rescheduled, completed, reopened, cancelled, archived, deleted
    case priorityChanged = "priority_changed"
    /// No longer written (estimates were replaced by time spent); kept so older logs still read.
    case estimateChanged = "estimate_changed"
    case sessionLinked = "session_linked"
}

public enum Actor: String, Codable, Sendable {
    case app, hermes, external, you
}

/// One line of `PastelFocus/Logs/events-YYYY-MM.jsonl`.
public struct TaskEvent: Codable, Sendable, Equatable {
    public var at: Date
    public var taskId: String
    public var type: TaskEventType
    public var field: String?
    public var old: String?
    public var new: String?
    public var actor: Actor
    public var reason: String?

    public init(at: Date, taskId: String, type: TaskEventType, field: String? = nil,
                old: String? = nil, new: String? = nil, actor: Actor, reason: String? = nil) {
        self.at = at; self.taskId = taskId; self.type = type; self.field = field
        self.old = old; self.new = new; self.actor = actor; self.reason = reason
    }
}

public enum SuggestionResponse: String, Codable, Sendable {
    case shown, accepted, dismissed, ignored, muted
}

/// One line of `PastelFocus/Logs/suggestions-YYYY-MM.jsonl`.
public struct SuggestionRecord: Codable, Sendable, Equatable {
    public var id: String
    public var kind: String
    public var at: Date
    public var response: SuggestionResponse
    public var why: String?

    public init(id: String, kind: String, at: Date, response: SuggestionResponse, why: String? = nil) {
        self.id = id; self.kind = kind; self.at = at; self.response = response; self.why = why
    }
}
