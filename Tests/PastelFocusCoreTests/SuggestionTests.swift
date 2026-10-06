import XCTest
@testable import PastelFocusCore

final class SuggestionTests: XCTestCase {
    let t0 = ISO8601.date("2026-10-20T11:30:00Z")!

    func insight(_ kind: String, scope: String = "all", value: Double, baseline: Double? = nil) -> Insight {
        Insight(kind: kind, scope: scope, title: kind, evidence: "evidence for \(kind)", value: value, baseline: baseline,
                sampleN: 14, days: 9, windowDays: 28, computedAt: t0)
    }

    var fatigue: Insight { insight("fatigue", scope: "session#4+", value: 0.64, baseline: 0.22) }

    func testBreakSuggestedOnlyAtTheRightBlockAndNeverMidSession() throws {
        let e = SuggestionEngine(calendar: dubai, history: [])
        XCTAssertNil(e.evaluate(.sessionEnd(blocksToday: 1), insights: [fatigue], now: t0, sessionRunning: false))
        XCTAssertNil(e.evaluate(.sessionEnd(blocksToday: 3), insights: [fatigue], now: t0, sessionRunning: true))
        let s = try XCTUnwrap(e.evaluate(.sessionEnd(blocksToday: 3), insights: [fatigue], now: t0, sessionRunning: false))
        XCTAssertEqual(s.action, .takeBreak(kind: .nsdr, minutes: 15))
        XCTAssertEqual(s.why, "evidence for fatigue")
    }

    func testLongBreakWhenNSDRDoesNotHelp() throws {
        let e = SuggestionEngine(calendar: dubai, history: [])
        let nsdr = insight("nsdr", value: 0.4, baseline: 0.3)
        let s = try XCTUnwrap(e.evaluate(.sessionEnd(blocksToday: 4), insights: [fatigue, nsdr], now: t0, sessionRunning: false))
        XCTAssertEqual(s.action, .takeBreak(kind: .longBreak, minutes: 20))
    }

    func testShorterSessionsAndEstimateAndPostponed() throws {
        let e = SuggestionEngine(calendar: dubai, history: [])
        let span = insight("focus_span", value: 41, baseline: 50)
        XCTAssertEqual(e.evaluate(.sessionStart(plannedMinutes: 50), insights: [span], now: t0, sessionRunning: false)?.action,
                       .useShorterSessions(minutes: 40))
        XCTAssertNil(e.evaluate(.sessionStart(plannedMinutes: 45), insights: [span], now: t0, sessionRunning: false))

        let task = TaskItem(taskID: "t1", description: "API work #coding", estimateSessions: 2)
        let est = insight("estimate", scope: "category:coding", value: 1.8)
        XCTAssertEqual(e.evaluate(.planning(task), insights: [est], now: t0, sessionRunning: false)?.action, .raiseEstimate(taskID: "t1", sessions: 4))
        let post = insight("postponed", scope: "task:t1", value: 3)
        XCTAssertEqual(e.evaluate(.planning(task), insights: [est, post], now: t0, sessionRunning: false)?.action, .splitOrDrop(taskID: "t1"))
    }

    func testBudgetLimits() {
        let e = SuggestionEngine(calendar: dubai, history: [])
        let s = e.evaluate(.sessionEnd(blocksToday: 3), insights: [fatigue], now: t0, sessionRunning: false)!
        e.record(s, .shown, at: t0)
        // 90-minute gap between any two cards.
        XCTAssertFalse(e.allowed(kind: "raise_estimate", now: t0.addingTimeInterval(60 * 60)))
        XCTAssertTrue(e.allowed(kind: "raise_estimate", now: t0.addingTimeInterval(91 * 60)))
        // Same kind at most once every 3 days.
        XCTAssertFalse(e.allowed(kind: "break_nsdr", now: t0.addingTimeInterval(2 * 86_400)))
        XCTAssertTrue(e.allowed(kind: "break_nsdr", now: t0.addingTimeInterval(3 * 86_400 + 60)))
    }

    func testMaxThreePerDay() {
        let e = SuggestionEngine(calendar: dubai, history: (0..<3).map {
            SuggestionRecord(id: "x\($0)", kind: "k\($0)", at: t0.addingTimeInterval(Double(-$0 - 1) * 2 * 3600 + 3600 * 0), response: .shown)
        })
        XCTAssertFalse(e.allowed(kind: "other", now: t0.addingTimeInterval(2 * 3600)))
    }

    func testTwoDismissalsPauseAKindAndMuteStopsIt() {
        let h = [SuggestionRecord(id: "a", kind: "break_nsdr", at: t0.addingTimeInterval(-10 * 86_400), response: .dismissed),
                 SuggestionRecord(id: "b", kind: "break_nsdr", at: t0.addingTimeInterval(-5 * 86_400), response: .dismissed)]
        let e = SuggestionEngine(calendar: dubai, history: h)
        XCTAssertFalse(e.allowed(kind: "break_nsdr", now: t0))
        XCTAssertTrue(e.allowed(kind: "break_nsdr", now: t0.addingTimeInterval(10 * 86_400)))
        let m = SuggestionEngine(calendar: dubai, history: [SuggestionRecord(id: "c", kind: "shorter_sessions", at: t0, response: .muted)])
        XCTAssertFalse(m.allowed(kind: "shorter_sessions", now: t0.addingTimeInterval(100 * 86_400)))
    }
}
