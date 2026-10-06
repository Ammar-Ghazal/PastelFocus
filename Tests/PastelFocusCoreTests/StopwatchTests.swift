import XCTest
@testable import PastelFocusCore

final class StopwatchTests: XCTestCase {
    let task = TaskRef(id: "r7q2", title: "Finalize resume", category: "career")

    func testCountsUpPastThePresetAndStoppingCompletes() throws {
        let clock = FixedClock("2026-10-07T06:00:00Z")
        let e = FocusEngine(clock: clock) // preset is 25 min, but a stopwatch ignores it
        try e.start(task: task, stopwatch: true)
        clock.advance(40 * 60)
        XCTAssertNil(e.tick(), "no end at 25 min")
        XCTAssertEqual(e.elapsedS, 2400)
        XCTAssertNil(e.countdownEnd, "no notification or widget countdown")
        let r = try e.stop(reason: "ignored")
        XCTAssertEqual(r.outcome, .completed)
        XCTAssertEqual(r.focusedS, 2400)
        XCTAssertEqual(r.plannedS, 2400, "planned = actual, so analytics never see it as cut short")
        XCTAssertEqual(r.preset, "stopwatch")
        XCTAssertNil(r.stopReason)
        XCTAssertTrue(r.isStopwatch)
    }

    func testPausesAreRecordedAndStartAccountsForThem() throws {
        let clock = FixedClock("2026-10-07T06:00:00Z")
        let e = FocusEngine(clock: clock)
        try e.start(task: nil, stopwatch: true)
        clock.advance(600); try e.pause()
        clock.advance(120); try e.resume()
        XCTAssertEqual(e.stopwatchStart, ISO8601.date("2026-10-07T06:02:00Z"), "start shifted by the pause for count-up widgets")
        clock.advance(300)
        let r = try e.stop()
        XCTAssertEqual(r.focusedS, 900)
        XCTAssertEqual(r.pauses, [PauseRecord(atS: 600, durS: 120)])
    }

    func testForgottenStopwatchFinishesAtTheCap() throws {
        let clock = FixedClock("2026-10-07T06:00:00Z")
        let e = FocusEngine(clock: clock)
        try e.start(task: task, stopwatch: true)
        clock.advance(5 * 3600)
        let r = try XCTUnwrap(e.tick())
        XCTAssertEqual(r.focusedS, 4 * 3600)
        XCTAssertEqual(r.endedAt, ISO8601.date("2026-10-07T10:00:00Z"))
    }

    func testOldSavedStateWithoutStopwatchKeyStillLoads() throws {
        let json = #"{"phase":"running","cycleIndex":0,"preset":{"focusMinutes":25,"shortRestMinutes":5,"longRestMinutes":15},"active":{"id":"s1234567","kind":"focus","plannedS":1500,"startedAt":0,"bankedS":0,"runningSince":0,"pauses":[]}}"#
        let snap = try JSONDecoder().decode(FocusSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snap.active?.isStopwatch, false)
    }

    func testFocusLogAndNowShowStopwatch() throws {
        let start = ISO8601.date("2026-10-07T06:00:00Z")!
        let r = SessionRecord(id: "s7654321", kind: .focus, taskId: "r7q2", taskTitle: "Resume", category: nil, preset: "stopwatch",
                              plannedS: 2520, startedAt: start, endedAt: start.addingTimeInterval(2520), tz: "Asia/Dubai",
                              focusedS: 2520, outcome: .completed)
        XCTAssertTrue(SessionRecorder.focusLogLine(r, calendar: dubai).contains("· 42 min (stopwatch) · completed"))
        let now = Reports.now(.init(appRunning: true, phase: .running, taskTitle: "Resume", taskID: "r7q2", kind: .focus,
                                    remainingS: 0, plannedS: 14400, stopwatch: true, elapsedS: 720),
                              today: [], rollup: nil, updated: start, calendar: dubai)
        XCTAssertTrue(now.contains("stopwatch, 12 min so far"), now)
    }

    func testStopwatchSessionsDontSkewFocusSpanPlan() {
        let engine = AnalyticsEngine(calendar: dubai)
        let now = ISO8601.date("2026-10-31T18:00:00Z")!
        var s: [SessionRecord] = []
        for i in 0..<16 {
            let start = now.addingTimeInterval(Double(-i) * 86_400)
            s.append(SessionRecord(id: "a\(i)", kind: .focus, taskId: nil, taskTitle: nil, category: nil, preset: "50/10",
                                   plannedS: 3000, startedAt: start, endedAt: start.addingTimeInterval(3000), tz: "Asia/Dubai",
                                   focusedS: 3000, outcome: .completed, pauses: [PauseRecord(atS: 40 * 60, durS: 60)]))
            s.append(SessionRecord(id: "b\(i)", kind: .focus, taskId: nil, taskTitle: nil, category: nil, preset: "stopwatch",
                                   plannedS: 600, startedAt: start.addingTimeInterval(4000), endedAt: start.addingTimeInterval(4600),
                                   tz: "Asia/Dubai", focusedS: 600, outcome: .completed))
        }
        let span = engine.insights(AnalyticsInput(sessions: s, events: [], tasks: []), now: now).first { $0.kind == "focus_span" }
        XCTAssertEqual(span?.baseline, 50, "planned length comes from countdown sessions only")
    }
}
