import Foundation

public struct FocusPreset: Codable, Sendable, Equatable {
    public var focusMinutes: Int
    public var shortRestMinutes: Int
    public var longRestMinutes: Int

    public init(focusMinutes: Int, shortRestMinutes: Int, longRestMinutes: Int) {
        self.focusMinutes = focusMinutes
        self.shortRestMinutes = shortRestMinutes
        self.longRestMinutes = longRestMinutes
    }

    public static let classic = FocusPreset(focusMinutes: 25, shortRestMinutes: 5, longRestMinutes: 15)
    public static let deep = FocusPreset(focusMinutes: 50, shortRestMinutes: 10, longRestMinutes: 20)

    public var name: String { "\(focusMinutes)/\(shortRestMinutes)" }

    /// Rest scaled to the chosen focus length: about a fifth, 3–20 min; long rest is three times that.
    public static func forFocus(_ minutes: Int) -> FocusPreset {
        let rest = min(20, max(3, Int((Double(minutes) / 5).rounded())))
        return FocusPreset(focusMinutes: minutes, shortRestMinutes: rest, longRestMinutes: rest * 3)
    }
}

/// The task a session is for. Nil task = "Unassigned".
public struct TaskRef: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var category: String?
    public init(id: String, title: String, category: String?) { self.id = id; self.title = title; self.category = category }
}

public enum FocusPhase: String, Codable, Sendable {
    case idle, running, paused, resting
}

/// The live session, saved to `state.json` so a restart resumes it.
public struct ActiveSession: Codable, Sendable, Equatable {
    public var id: String
    public var kind: SessionKind
    public var task: TaskRef?
    public var plannedS: Int
    public var startedAt: Date
    /// Focus seconds banked before the current running stretch.
    public var bankedS: Int
    /// Set while running.
    public var runningSince: Date?
    /// Set while paused.
    public var pausedAt: Date?
    public var pauses: [PauseRecord]
    /// Counts up with no end time (nil in state saved by older versions).
    public var stopwatch: Bool? = nil

    public var isStopwatch: Bool { stopwatch == true }
}

public struct FocusSnapshot: Codable, Sendable, Equatable {
    public var phase: FocusPhase
    public var active: ActiveSession?
    public var cycleIndex: Int
    public var preset: FocusPreset
}

/// Timer state machine: Idle → Running ⇄ Paused → Completed | Abandoned, then optional Rest.
/// Time always comes from `clock`, so the timer survives sleep, App Nap and restarts.
public final class FocusEngine {
    public private(set) var phase: FocusPhase = .idle
    public private(set) var active: ActiveSession?
    /// Position in the 4-step cycle: 0 focus · 1 short rest · 2 focus · 3 long rest.
    public private(set) var cycleIndex = 0
    public var preset: FocusPreset

    let clock: Clock
    let tzName: String
    /// A pause longer than this ends the session as "paused out".
    public var maxPauseS = 15 * 60
    /// Sleep longer than this during a running session ends it as "sleep interrupted".
    public var sleepThresholdS = 120
    /// A stopwatch that runs this long is finished automatically (forgotten timers shouldn't log 20 h of focus).
    public var stopwatchCapS = 4 * 3600

    public init(clock: Clock, preset: FocusPreset = .classic, tzName: String = TimeZone.current.identifier) {
        self.clock = clock
        self.preset = preset
        self.tzName = tzName
    }

    // MARK: Derived values

    public var focusedS: Int {
        guard let a = active else { return 0 }
        let running = a.runningSince.map { Int(clock.now().timeIntervalSince($0)) } ?? 0
        return min(a.plannedS, a.bankedS + max(0, running))
    }

    public var remainingS: Int { max(0, (active?.plannedS ?? preset.focusMinutes * 60) - focusedS) }

    /// Seconds counted so far (what a stopwatch shows).
    public var elapsedS: Int { focusedS }

    public var isStopwatch: Bool { active?.isStopwatch ?? false }

    /// When a countdown hits 00:00, for notifications and widgets. Nil for a stopwatch.
    public var countdownEnd: Date? { isStopwatch ? nil : endDate }

    /// When a running stopwatch started counting, adjusted for pauses (lets widgets count up by themselves).
    public var stopwatchStart: Date? {
        guard isStopwatch, let a = active, let since = a.runningSince else { return nil }
        return since.addingTimeInterval(-TimeInterval(a.bankedS))
    }

    /// When the running session ends on its own (for a stopwatch: the safety cap).
    public var endDate: Date? {
        guard let a = active, let since = a.runningSince else { return nil }
        return since.addingTimeInterval(TimeInterval(a.plannedS - a.bankedS))
    }

    public var snapshot: FocusSnapshot { FocusSnapshot(phase: phase, active: active, cycleIndex: cycleIndex, preset: preset) }

    public func restore(_ s: FocusSnapshot) {
        phase = s.phase; active = s.active; cycleIndex = s.cycleIndex; preset = s.preset
    }

    public enum EngineError: Error, Equatable { case busy, notRunning, notPaused, notResting }

    // MARK: Commands

    /// Starts a countdown of `minutes` (default: the preset), or a stopwatch that counts up.
    public func start(task: TaskRef?, minutes: Int? = nil, stopwatch: Bool = false) throws {
        guard phase == .idle else { throw EngineError.busy }
        let planned = stopwatch ? stopwatchCapS : (minutes ?? preset.focusMinutes) * 60
        let now = clock.now()
        active = ActiveSession(id: Self.newSessionID(), kind: .focus, task: task, plannedS: planned,
                               startedAt: now, bankedS: 0, runningSince: now, pausedAt: nil, pauses: [],
                               stopwatch: stopwatch ? true : nil)
        if cycleIndex % 2 == 1 { cycleIndex = (cycleIndex + 1) % 4 }
        phase = .running
    }

    public func pause() throws {
        guard phase == .running, var a = active, let since = a.runningSince else { throw EngineError.notRunning }
        let now = clock.now()
        a.bankedS = min(a.plannedS, a.bankedS + Int(now.timeIntervalSince(since)))
        a.runningSince = nil
        a.pausedAt = now
        active = a
        phase = .paused
    }

    public func resume() throws {
        guard phase == .paused, var a = active, let pausedAt = a.pausedAt else { throw EngineError.notPaused }
        let now = clock.now()
        a.pauses.append(PauseRecord(atS: a.bankedS, durS: Int(now.timeIntervalSince(pausedAt))))
        a.pausedAt = nil
        a.runningSince = now
        active = a
        phase = .running
    }

    /// Stops. Countdowns end as "stopped early", rests as "skipped"; a stopwatch has no target,
    /// so stopping it is how it finishes ("completed").
    public func stop(reason: String? = nil) throws -> SessionRecord {
        guard phase != .idle, let a = active else { throw EngineError.notRunning }
        if a.isStopwatch { return finish(at: clock.now(), outcome: .completed, reason: nil) }
        let outcome: SessionOutcome = a.kind == .focus ? .stoppedEarly : .skipped
        return finish(at: clock.now(), outcome: outcome, reason: reason)
    }

    /// Begins a rest. Defaults to the cycle's next rest kind.
    public func startRest(kind: SessionKind? = nil, minutes: Int? = nil) throws {
        guard phase == .idle else { throw EngineError.busy }
        let k = kind ?? nextRestKind
        let mins = minutes ?? (k == .longBreak ? preset.longRestMinutes : k == .nsdr ? 15 : preset.shortRestMinutes)
        let now = clock.now()
        active = ActiveSession(id: Self.newSessionID(), kind: k, task: nil, plannedS: mins * 60,
                               startedAt: now, bankedS: 0, runningSince: now, pausedAt: nil, pauses: [])
        phase = .resting
    }

    public var nextRestKind: SessionKind { cycleIndex >= 2 ? .longBreak : .shortBreak }

    /// Call every second (and on wake). Returns a record when a session ends on its own.
    public func tick() -> SessionRecord? {
        guard let a = active else { return nil }
        let now = clock.now()
        if phase == .paused, let pausedAt = a.pausedAt, now.timeIntervalSince(pausedAt) > TimeInterval(maxPauseS) {
            var copy = a
            copy.pauses.append(PauseRecord(atS: a.bankedS, durS: maxPauseS))
            copy.pausedAt = nil
            active = copy
            return finish(at: pausedAt.addingTimeInterval(TimeInterval(maxPauseS)), outcome: .pausedOut, reason: "paused out")
        }
        if (phase == .running || phase == .resting), let end = endDate, now >= end {
            return finish(at: end, outcome: .completed, reason: nil)
        }
        return nil
    }

    /// The Mac slept from `from` to `to`. A running focus session that slept too long ends at `from`.
    public func handleSleep(from: Date, to: Date) -> SessionRecord? {
        guard phase == .running, let a = active, let since = a.runningSince,
              to.timeIntervalSince(from) > TimeInterval(sleepThresholdS) else { return tick() }
        if let end = endDate, end <= from { return finish(at: end, outcome: .completed, reason: nil) }
        var copy = a
        copy.bankedS = min(a.plannedS, a.bankedS + Int(from.timeIntervalSince(since)))
        copy.runningSince = nil
        active = copy
        return finish(at: from, outcome: .sleepInterrupted, reason: "Mac slept")
    }

    // MARK: Internals

    private func finish(at end: Date, outcome: SessionOutcome, reason: String?) -> SessionRecord {
        var a = active!
        if let since = a.runningSince {
            a.bankedS = min(a.plannedS, a.bankedS + max(0, Int(end.timeIntervalSince(since))))
        }
        if let pausedAt = a.pausedAt {
            a.pauses.append(PauseRecord(atS: a.bankedS, durS: Int(end.timeIntervalSince(pausedAt))))
        }
        let focused = outcome == .completed && !a.isStopwatch ? a.plannedS : a.bankedS
        // A stopwatch has no plan: record planned = actual so analytics never read it as cut short.
        let record = SessionRecord(id: a.id, kind: a.kind, taskId: a.task?.id, taskTitle: a.task?.title,
                                   category: a.task?.category, preset: a.isStopwatch ? "stopwatch" : preset.name,
                                   plannedS: a.isStopwatch ? focused : a.plannedS,
                                   startedAt: a.startedAt, endedAt: end, tz: tzName, focusedS: focused,
                                   outcome: outcome, stopReason: reason, pauses: a.pauses)
        if a.kind == .focus, outcome == .completed { cycleIndex = (cycleIndex + 1) % 4 }
        if a.kind.isBreak { cycleIndex = (cycleIndex + 1) % 4 }
        active = nil
        phase = .idle
        return record
    }

    static func newSessionID() -> String { "s" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(7).lowercased() }
}
