import XCTest
@testable import PastelFocusCore

final class TaskStoreTests: XCTestCase {
    var config: VaultConfig!
    var clock: FixedClock!
    var store: TaskStore!

    override func setUp() {
        config = makeVault()
        clock = FixedClock("2026-10-07T06:00:00Z") // 10:00 in Dubai
        store = TaskStore(config: config, calendar: dubai, clock: clock)
        write("""
        # Career Plan

        ## Today's task list

        - [ ] Finalize resume #career ⏫ [est:: 3] 🆔 r7q2
            - Use the SWE template
        - [ ] Old legacy task without id
        - [x] Done earlier 🆔 d0n3 ✅ 2026-10-06

        ## End-of-day check-in

        - Energy, morning (1–5):
        """, to: config.dailyNote("2026-10-06"))
        write("""
        # Career Plan

        ## Today's task list

        - [ ] Pick target countries #career 🔼 🆔 c4x8
        """, to: config.dailyNote("2026-10-07"))
        write("# Backlog\n\n## Tasks\n\n- [ ] Someday task #later 🆔 b1b1\n- [ ] Future task ⏳ 2026-10-09 🆔 f1f1\n", to: config.backlog)
    }

    func testScanReadsNotesAndBacklog() {
        let tasks = store.scan().tasks
        XCTAssertEqual(tasks.count, 6)
        XCTAssertEqual(tasks.first { $0.taskID == "r7q2" }?.notes, ["Use the SWE template"])
    }

    func testTodayIncludesOverdueAndExcludesFutureAndBacklog() {
        let ids = store.todayTasks(store.scan().tasks).map(\.title)
        XCTAssertEqual(Set(ids), ["Finalize resume", "Old legacy task without id", "Pick target countries"])
    }

    func testStampMissingIDsOnlyTouchesThatLine() throws {
        let before = read(config.dailyNote("2026-10-06"))
        XCTAssertEqual(try store.stampMissingIDs(), 1)
        let after = read(config.dailyNote("2026-10-06"))
        XCTAssertTrue(after.contains("- [ ] Old legacy task without id 🆔 "))
        // Everything else is byte-for-byte unchanged.
        let changed = zip(before.split(separator: "\n"), after.split(separator: "\n")).filter { $0 != $1 }
        XCTAssertEqual(changed.count, 1)
        XCTAssertEqual(try store.stampMissingIDs(), 0)
    }

    func testCompleteLogsEventAndDate() throws {
        try store.setStatus("r7q2", .done, actor: .you)
        let t = try XCTUnwrap(store.find("r7q2"))
        XCTAssertEqual(t.status, .done)
        XCTAssertEqual(t.completed, "2026-10-07")
        let e = store.events.readAll()
        XCTAssertEqual(e.count, 1)
        XCTAssertEqual(e[0].type, .completed)
        XCTAssertEqual(e[0].actor, .you)
        // Reopen removes the done date.
        try store.setStatus("r7q2", .todo, actor: .you)
        XCTAssertNil(store.find("r7q2")?.completed)
        XCTAssertEqual(store.events.readAll().last?.type, .reopened)
    }

    func testRescheduleRecordsOldAndNewDay() throws {
        try store.reschedule("r7q2", to: "2026-10-09", actor: .hermes, reason: "waiting on references")
        let e = try XCTUnwrap(store.events.readAll().last)
        XCTAssertEqual(e.type, .rescheduled)
        XCTAssertEqual(e.old, "2026-10-06")
        XCTAssertEqual(e.new, "2026-10-09")
        XCTAssertEqual(e.reason, "waiting on references")
        XCTAssertFalse(store.todayTasks(store.scan().tasks).contains { $0.taskID == "r7q2" })
    }

    func testCreateGoesToTodayOrBacklog() throws {
        let a = try store.create(TaskItem(description: "Mock interview #learning", priority: .high, estimateSessions: 2), actor: .hermes)
        XCTAssertEqual(a.file, config.relativePath(config.dailyNote("2026-10-07")))
        XCTAssertTrue(read(config.dailyNote("2026-10-07")).contains("- [ ] Mock interview #learning [est:: 2] ⏫ ➕ 2026-10-07 🆔 \(a.taskID!)"))
        let b = try store.create(TaskItem(description: "Later thing", scheduled: "2026-10-12"), actor: .you)
        XCTAssertEqual(b.file, config.relativePath(config.backlog))
        XCTAssertEqual(store.events.readAll().filter { $0.type == .created }.count, 2)
    }

    func testCreateMakesTodaysNoteWhenMissing() throws {
        try FileManager.default.removeItem(at: config.dailyNote("2026-10-07"))
        _ = try store.create(TaskItem(description: "First task"), actor: .you)
        let text = read(config.dailyNote("2026-10-07"))
        XCTAssertTrue(text.contains("# Career Plan — Wednesday, October 7, 2026"))
        XCTAssertTrue(text.contains("## Today's task list\n\n- [ ] First task"))
    }

    func testDeleteRemovesLineAndNotesThenRestores() throws {
        let url = config.dailyNote("2026-10-06")
        let before = SafeFile.readLines(url)
        let removed = try store.delete("r7q2", actor: .you)
        XCTAssertEqual(removed.lines, ["- [ ] Finalize resume #career ⏫ [est:: 3] 🆔 r7q2", "    - Use the SWE template"])
        XCTAssertNil(store.find("r7q2"))
        let after = SafeFile.readLines(url)
        XCTAssertEqual(after.count, before.count - 2)
        XCTAssertTrue(after.contains("- [ ] Old legacy task without id"), "neighbouring lines stay")
        XCTAssertEqual(store.events.readAll().last?.type, .deleted)

        try store.restore(removed, actor: .you)
        XCTAssertEqual(SafeFile.readLines(url), before, "Undo puts the lines back exactly")
        XCTAssertEqual(store.find("r7q2")?.notes, ["Use the SWE template"])
        try store.restore(removed, actor: .you) // already back: no duplicate
        XCTAssertEqual(SafeFile.readLines(url), before)
    }

    func testEditorSaveWritesOnlyChangedFields() throws {
        let original = try XCTUnwrap(store.find("r7q2"))
        // Hermes logs a session while the editor is open.
        try store.setActualSessions("r7q2", 2)
        var edited = original
        edited.description = "Finalize resume — SWE version #career #writing"
        edited.priority = .urgent
        edited.due = "2026-10-10"
        edited.notes = ["Use the SWE template", "  Ask Sam to review  ", ""]
        let saved = try store.apply("r7q2", from: original, to: edited, actor: .you)
        XCTAssertEqual(saved.actualSessions, 2, "the concurrent change survives")
        XCTAssertEqual(saved.estimateSessions, 3)
        let lines = SafeFile.readLines(config.dailyNote("2026-10-06"))
        let i = try XCTUnwrap(lines.firstIndex { $0.contains("🆔 r7q2") })
        XCTAssertEqual(lines[i], "- [ ] Finalize resume — SWE version #career #writing [est:: 3] [sessions:: 2] 🔺 📅 2026-10-10 🆔 r7q2")
        XCTAssertEqual(Array(lines[(i + 1)...(i + 2)]), ["    - Use the SWE template", "    - Ask Sam to review"])
        XCTAssertEqual(lines[i + 3], "- [ ] Old legacy task without id")
        let types = store.events.readAll().filter { $0.taskId == "r7q2" && $0.actor == .you }.map { $0.field ?? "" }
        XCTAssertEqual(Set(types), ["priority", "description", "due", "notes"])
    }

    func testEditorAddsNotesAndCompletes() throws {
        let original = try XCTUnwrap(store.find("c4x8"))
        var edited = original
        edited.notes = ["First note"]
        edited.status = .done
        try store.apply("c4x8", from: original, to: edited, actor: .you)
        let lines = SafeFile.readLines(config.dailyNote("2026-10-07"))
        XCTAssertEqual(lines.suffix(2), ["- [x] Pick target countries #career 🔼 ✅ 2026-10-07 🆔 c4x8", "    - First note"])
        XCTAssertEqual(store.events.readAll().last { $0.taskId == "c4x8" && $0.field == "status" }?.type, .completed)
        // Saving with nothing changed leaves the file alone.
        let now = try XCTUnwrap(store.find("c4x8"))
        try store.apply("c4x8", from: now, to: now, actor: .you)
        XCTAssertEqual(SafeFile.readLines(config.dailyNote("2026-10-07")), lines)
    }

    func testEditingLegacyLineWritesPriorityEmoji() throws {
        write("## Today's task list\n\n- [ ] **P2 · 50 min** Old plan 🆔 leg1\n", to: config.dailyNote("2026-10-05"))
        let original = try XCTUnwrap(store.find("leg1"))
        var edited = original
        edited.description = "Old plan, renamed"
        try store.apply("leg1", from: original, to: edited, actor: .you)
        XCTAssertEqual(SafeFile.readLines(config.dailyNote("2026-10-05")).last, "- [ ] Old plan, renamed [est:: 2] 🔼 🆔 leg1")
    }

    func testDiffDetectsExternalEdits() {
        let old = store.scan().tasks
        var new = old
        let i = new.firstIndex { $0.taskID == "c4x8" }!
        new[i].status = .done
        new[i].priority = .high
        new[i].scheduled = "2026-10-08"
        let events = TaskStore.diff(old: old, new: new, at: clock.now(), defaultDay: store.effectiveDay)
        XCTAssertEqual(Set(events.map(\.type)), [.completed, .priorityChanged, .rescheduled])
        XCTAssertTrue(events.allSatisfy { $0.actor == .external })
    }

    func testProblemsForBadDatesAndDuplicates() throws {
        write("## Today's task list\n\n- [ ] Bad date 📅 tomorrow 🆔 zz11\n- [ ] Copy 🆔 r7q2\n", to: config.dailyNote("2026-10-05"))
        let problems = store.scan().problems
        XCTAssertEqual(problems.count, 2)
        try store.writeProblems(problems)
        XCTAssertTrue(read(config.problems).contains("duplicate 🆔 r7q2"))
        try store.writeProblems([])
        XCTAssertFalse(FileManager.default.fileExists(atPath: config.problems.path))
    }

    func testSafeFileDetectsConcurrentWrite() {
        let url = config.backlog
        XCTAssertThrowsError(try SafeFile.edit(url, retries: 0) { lines in
            // Someone else writes while we are editing.
            try! "changed by someone else\n".write(to: url, atomically: true, encoding: .utf8)
            lines.append("mine")
        }) { XCTAssertEqual($0 as? SafeFileError, .conflict("Backlog.md")) }
        XCTAssertEqual(read(url), "changed by someone else\n")
    }
}
