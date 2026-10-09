import XCTest
@testable import PastelFocusCore

final class RecurrenceTests: XCTestCase {
    // 2026-10-09 is a Friday.
    let cal = dubai

    func testReadsTheSupportedRules() {
        XCTAssertEqual(Recurrence("every day"), Recurrence(unit: .day))
        XCTAssertEqual(Recurrence("every 3 days"), Recurrence(interval: 3, unit: .day))
        XCTAssertEqual(Recurrence("every week"), Recurrence(unit: .week))
        XCTAssertEqual(Recurrence("every 2 weeks"), Recurrence(interval: 2, unit: .week))
        XCTAssertEqual(Recurrence("biweekly"), Recurrence(interval: 2, unit: .week))
        XCTAssertEqual(Recurrence("every other week"), Recurrence(interval: 2, unit: .week))
        XCTAssertEqual(Recurrence("every week on Monday, Thursday"), Recurrence(unit: .week, weekdays: [1, 4]))
        XCTAssertEqual(Recurrence("every Tuesday and Friday"), Recurrence(unit: .week, weekdays: [2, 5]))
        XCTAssertEqual(Recurrence("every weekday"), Recurrence(unit: .week, weekdays: [1, 2, 3, 4, 5]))
        XCTAssertEqual(Recurrence("every weekend"), Recurrence(unit: .week, weekdays: [6, 7]))
        XCTAssertEqual(Recurrence("every month when done"), Recurrence(unit: .month, whenDone: true))
        XCTAssertNil(Recurrence("every blue moon"))
        XCTAssertNil(Recurrence("sometimes"))
    }

    func testCanonicalText() {
        XCTAssertEqual(Recurrence("every week on thu, mon")?.text, "every week on Monday, Thursday")
        XCTAssertEqual(Recurrence("biweekly")?.text, "every 2 weeks")
        XCTAssertEqual(Recurrence("every weekday")?.text, "every weekday")
        XCTAssertEqual(Recurrence("every day when done")?.text, "every day when done")
    }

    func testNextDates() {
        XCTAssertEqual(Recurrence("every day")?.next(after: "2026-10-09", calendar: cal), "2026-10-10")
        XCTAssertEqual(Recurrence("every week")?.next(after: "2026-10-09", calendar: cal), "2026-10-16")
        XCTAssertEqual(Recurrence("every 2 weeks")?.next(after: "2026-10-09", calendar: cal), "2026-10-23")
        XCTAssertEqual(Recurrence("every weekday")?.next(after: "2026-10-09", calendar: cal), "2026-10-12") // Fri → Mon
        XCTAssertEqual(Recurrence("every weekend")?.next(after: "2026-10-09", calendar: cal), "2026-10-10")
        XCTAssertEqual(Recurrence("every weekend")?.next(after: "2026-10-11", calendar: cal), "2026-10-17") // Sun → Sat
        // Biweekly on Monday and Friday, from a Monday: Friday that week, then Monday two weeks on.
        let r = Recurrence("every 2 weeks on Monday, Friday")!
        XCTAssertEqual(r.next(after: "2026-10-05", calendar: cal), "2026-10-09")
        XCTAssertEqual(r.next(after: "2026-10-09", calendar: cal), "2026-10-19")
        XCTAssertEqual(Recurrence("every month")?.next(after: "2026-01-31", calendar: cal), "2026-02-28")
    }
}

final class SchedulingTests: XCTestCase {
    var config: VaultConfig!
    var clock: FixedClock!
    var store: TaskStore!

    override func setUp() {
        config = makeVault()
        clock = FixedClock("2026-10-09T05:00:00Z") // Friday 09:00 in Dubai
        store = TaskStore(config: config, calendar: dubai, clock: clock)
        write("""
        ## Today's task list

        - [ ] 07:00 - 07:30 Stretch #health 🔁 every weekday 🆔 st01
        - [ ] Weekly review 🔁 every week ⏳ 2026-10-02 📅 2026-10-03 🆔 wr01
        - [ ] One-off 🆔 one1
        """, to: config.dailyNote("2026-10-09"))
    }

    func testCompletingARoutineAddsTheNextOne() throws {
        let next = try XCTUnwrap(store.setStatus("st01", .done, actor: .you))
        XCTAssertEqual(next.scheduled, "2026-10-12") // Friday → Monday
        XCTAssertEqual(next.startTime, "07:00")
        XCTAssertEqual(next.durationMinutes, 30)
        XCTAssertEqual(next.recurrence, "every weekday")
        XCTAssertNotEqual(next.taskID, "st01")
        XCTAssertTrue(read(config.backlog).contains("- [ ] 07:00 - 07:30 Stretch #health 🔁 every weekday ➕ 2026-10-09 ⏳ 2026-10-12 🆔 \(next.taskID!)"))
        XCTAssertEqual(store.events.readAll().last?.reason, "repeats every weekday")
        // Today shows the done one; the next one isn't listed as upcoming (it repeats).
        let all = store.scan().tasks
        XCTAssertTrue(store.todayTasks(all).contains { $0.taskID == "st01" && $0.status == .done })
        XCTAssertFalse(store.upcomingTasks(all).contains { $0.taskID == next.taskID })
        // Reopening and completing again doesn't add a second copy.
        try store.setStatus("st01", .todo, actor: .you)
        XCTAssertNil(try store.setStatus("st01", .done, actor: .you))
    }

    func testOverdueRoutineMovesToTodayAndShiftsDue() throws {
        let next = try XCTUnwrap(store.setStatus("wr01", .done, actor: .you))
        XCTAssertEqual(next.scheduled, nil, "today's occurrence goes in today's note")
        XCTAssertEqual(next.file, config.relativePath(config.dailyNote("2026-10-09")))
        XCTAssertEqual(next.due, "2026-10-10") // moved by the same 7 days
    }

    func testOneOffAndProgressCompletion() throws {
        XCTAssertNil(try store.setStatus("one1", .done, actor: .you))
        XCTAssertNotNil(try store.setProgress("st01", 100, actor: .you), "100% completes a routine too")
    }

    func testTimeAndRepeatSettersAndInbox() throws {
        try store.setTime("one1", start: "15:00", minutes: 45, actor: .hermes)
        try store.setRecurrence("one1", "every Monday and Friday", actor: .hermes)
        let t = try XCTUnwrap(store.find("one1"))
        XCTAssertEqual(t.timeLabel, "15:00–15:45")
        XCTAssertEqual(t.recurrence, "every week on Monday, Friday", "stored in canonical words")
        XCTAssertEqual(try InboxProcessor.parse("schedule 🆔 one1 07:00 - 07:45").command, .schedule(id: "one1", start: "07:00", minutes: 45))
        XCTAssertEqual(try InboxProcessor.parse("schedule 🆔 one1 45m").command, .schedule(id: "one1", start: nil, minutes: 45))
        XCTAssertEqual(try InboxProcessor.parse("schedule 🆔 one1 none").command, .schedule(id: "one1", start: nil, minutes: nil))
        XCTAssertEqual(try InboxProcessor.parse("repeat 🆔 one1 🔁 every 2 weeks on Friday").command, .repeats(id: "one1", rule: "every 2 weeks on Friday"))
        XCTAssertEqual(try InboxProcessor.parse("repeat 🆔 one1 never").command, .repeats(id: "one1", rule: nil))
        XCTAssertThrowsError(try InboxProcessor.parse("repeat 🆔 one1 whenever"))
    }

    func testTimeOfDaySort() {
        let tasks = [TaskItem(taskID: "a", description: "No time", priority: .urgent),
                     TaskItem(taskID: "b", description: "Late", startTime: "15:00"),
                     TaskItem(taskID: "c", description: "Early", startTime: "07:00")]
        XCTAssertEqual(TaskSort.time.sorted(tasks).map(\.taskID), ["c", "b", "a"])
    }
}
