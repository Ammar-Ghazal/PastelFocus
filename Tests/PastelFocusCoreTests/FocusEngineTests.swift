import XCTest
@testable import PastelFocusCore

final class FocusEngineTests: XCTestCase {
    let task = TaskRef(id: "r7q2", title: "Finalize resume", category: "career")

    func testCompletesAtPlannedTime() throws {
        let clock = FixedClock("2026-10-07T06:00:00Z")
        let e = FocusEngine(clock: clock)
        try e.start(task: task)
        clock.advance(24 * 60)
        XCTAssertNil(e.tick())
        XCTAssertEqual(e.remainingS, 60)
        clock.advance(90) // tick fires late, e.g. after App Nap
        let r = try XCTUnwrap(e.tick())
        XCTAssertEqual(r.outcome, .completed)
        XCTAssertEqual(r.focusedS, 1500)
        XCTAssertEqual(r.endedAt, ISO8601.date("2026-10-07T06:25:00Z"))
        XCTAssertEqual(e.phase, .idle)
        XCTAssertEqual(e.nextRestKind, .shortBreak)
    }

    func testPauseResumeRecordsPauseAndShiftsEnd() throws {
        let clock = FixedClock("2026-10-07T06:00:00Z")
        let e = FocusEngine(clock: clock)
        try e.start(task: task)
        clock.advance(600)
        try e.pause()
        clock.advance(180)
        XCTAssertEqual(e.focusedS, 600)
        try e.resume()
        XCTAssertEqual(e.endDate, ISO8601.date("2026-10-07T06:28:00Z"))
        clock.advance(900)
        let r = try XCTUnwrap(e.tick())
        XCTAssertEqual(r.pauses, [PauseRecord(atS: 600, durS: 180)])
        XCTAssertEqual(r.secondsToFirstInterruption, 600)
    }

    func testSwitchingTaskSplitsTheSessionAndKeepsTheTimer() throws {
        let clock = FixedClock("2026-10-07T06:00:00Z")
        let e = FocusEngine(clock: clock)
        try e.start(task: task)
        clock.advance(600)
        let other = TaskRef(id: "c4x8", title: "Pick countries", category: "career")
        let r = try e.switchTask(to: other)
        XCTAssertEqual(r.taskId, "r7q2")
        XCTAssertEqual(r.outcome, .switched)
        XCTAssertFalse(r.outcome.isInterrupted)
        XCTAssertEqual(r.focusedS, 600)
        XCTAssertEqual(r.plannedS, 600) // the rest of the plan moved to the next session
        XCTAssertEqual(e.phase, .running)
        XCTAssertEqual(e.active?.task, other)
        XCTAssertEqual(e.remainingS, 900)
        clock.advance(900)
        XCTAssertEqual(try XCTUnwrap(e.tick()).outcome, .completed)
        XCTAssertEqual(e.nextRestKind, .shortBreak) // one focus block, not two
    }

    func testSwitchingWhilePausedStaysPausedAndStopwatchRestarts() throws {
        let clock = FixedClock("2026-10-07T06:00:00Z")
        let e = FocusEngine(clock: clock)
        try e.start(task: task, stopwatch: true)
        clock.advance(300)
        try e.pause()
        let r = try e.switchTask(to: nil)
        XCTAssertEqual(r.focusedS, 300)
        XCTAssertEqual(e.phase, .paused)
        XCTAssertTrue(e.isStopwatch)
        XCTAssertEqual(e.elapsedS, 0)
        XCTAssertNil(e.active?.task)
    }

    func testCannotSwitchWhenIdleOrResting() throws {
        let e = FocusEngine(clock: FixedClock("2026-10-07T06:00:00Z"))
        XCTAssertThrowsError(try e.switchTask(to: task))
        try e.startRest()
        XCTAssertThrowsError(try e.switchTask(to: task))
    }

    func testStopEarlyIsLoggedWithReason() throws {
        let clock = FixedClock("2026-10-07T06:00:00Z")
        let e = FocusEngine(clock: clock)
        try e.start(task: task)
        clock.advance(720)
        let r = try e.stop(reason: "interrupted")
        XCTAssertEqual(r.outcome, .stoppedEarly)
        XCTAssertEqual(r.focusedS, 720)
        XCTAssertEqual(r.stopReason, "interrupted")
        XCTAssertEqual(e.nextRestKind, .shortBreak, "a stopped session doesn't advance the cycle")
    }

    func testLongPauseEndsAsPausedOut() throws {
        let clock = FixedClock("2026-10-07T06:00:00Z")
        let e = FocusEngine(clock: clock)
        try e.start(task: task)
        clock.advance(300)
        try e.pause()
        clock.advance(16 * 60)
        let r = try XCTUnwrap(e.tick())
        XCTAssertEqual(r.outcome, .pausedOut)
        XCTAssertEqual(r.focusedS, 300)
        XCTAssertEqual(r.endedAt, ISO8601.date("2026-10-07T06:20:00Z"))
    }

    func testSleepInterruptsRunningSession() throws {
        let clock = FixedClock("2026-10-07T06:00:00Z")
        let e = FocusEngine(clock: clock)
        try e.start(task: task)
        let sleptAt = ISO8601.date("2026-10-07T06:10:00Z")!
        clock.set("2026-10-07T07:00:00Z")
        let r = try XCTUnwrap(e.handleSleep(from: sleptAt, to: clock.now()))
        XCTAssertEqual(r.outcome, .sleepInterrupted)
        XCTAssertEqual(r.focusedS, 600)
        XCTAssertEqual(r.endedAt, sleptAt)
    }

    func testShortSleepIsIgnored() throws {
        let clock = FixedClock("2026-10-07T06:00:00Z")
        let e = FocusEngine(clock: clock)
        try e.start(task: task)
        clock.advance(600)
        XCTAssertNil(e.handleSleep(from: clock.now().addingTimeInterval(-60), to: clock.now()))
        XCTAssertEqual(e.phase, .running)
    }

    func testCycleFocusRestFocusLongRest() throws {
        let clock = FixedClock("2026-10-07T06:00:00Z")
        let e = FocusEngine(clock: clock)
        for expected in [SessionKind.shortBreak, .longBreak] {
            try e.start(task: nil)
            clock.advance(1500); _ = e.tick()
            XCTAssertEqual(e.nextRestKind, expected)
            try e.startRest()
            XCTAssertEqual(e.active?.kind, expected)
            clock.advance(Double(expected == .longBreak ? 900 : 300)); _ = e.tick()
        }
        XCTAssertEqual(e.cycleIndex, 0)
    }

    func testSnapshotRestoresAcrossRestart() throws {
        let clock = FixedClock("2026-10-07T06:00:00Z")
        let e = FocusEngine(clock: clock)
        try e.start(task: task)
        clock.advance(400)
        let data = try JSONEncoder().encode(e.snapshot)
        let e2 = FocusEngine(clock: clock)
        e2.restore(try JSONDecoder().decode(FocusSnapshot.self, from: data))
        XCTAssertEqual(e2.focusedS, 400)
        XCTAssertEqual(e2.phase, .running)
    }

    func testRecorderWritesLogNoteAndSessionCount() throws {
        let config = makeVault()
        let clock = FixedClock("2026-10-07T05:02:00Z")
        let store = TaskStore(config: config, calendar: dubai, clock: clock)
        write("## Today's task list\n\n- [ ] Finalize resume #career [est:: 3] 🆔 r7q2\n", to: config.dailyNote("2026-10-07"))
        let recorder = SessionRecorder(config: config, calendar: dubai, store: store)
        let e = FocusEngine(clock: clock, tzName: "Asia/Dubai")
        try e.start(task: task)
        clock.advance(1500)
        try recorder.record(XCTUnwrap(e.tick()))

        XCTAssertEqual(recorder.log.readAll().count, 1)
        XCTAssertEqual(store.find("r7q2")?.actualSessions, 1)
        let note = read(config.dailyNote("2026-10-07"))
        XCTAssertTrue(note.contains("## Focus log\n\n- 09:02–09:27 · 🆔 r7q2 · Finalize resume · 25/25 min · completed · pauses 0"), note)
        XCTAssertTrue(FileManager.default.fileExists(atPath: config.logsDir.appendingPathComponent("sessions-2026-10.jsonl").path))
    }

    func testPrivateLogsStayOutOfVault() throws {
        let config = makeVault(logsInVault: false)
        XCTAssertFalse(config.logsDir.path.hasPrefix(config.appDir.path))
    }
}
