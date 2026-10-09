import XCTest
@testable import PastelFocusCore

/// End-to-end flows against a temp vault: what the app does when files change, the timer ends, or night falls.
final class CoordinatorTests: XCTestCase {
    var config: VaultConfig!
    var clock: FixedClock!
    var support: URL!
    var c: Coordinator!

    override func setUp() {
        config = makeVault()
        clock = FixedClock("2026-10-07T05:00:00Z")
        support = config.root.appendingPathComponent(".support")
        write("## Today's task list\n\n- [ ] Finalize resume #career ⏫ [est:: 2] 🆔 r7q2\n- [ ] Legacy line\n", to: config.dailyNote("2026-10-07"))
        c = Coordinator(config: config, calendar: dubai, clock: clock, supportDir: support)
    }

    func testFirstRefreshStampsIDsAndWritesGeneratedFiles() {
        let external = c.refresh()
        XCTAssertTrue(external.isEmpty, "the first scan is a baseline, not a change")
        XCTAssertEqual(c.todayTasks.count, 2)
        XCTAssertTrue(c.todayTasks.allSatisfy { $0.taskID != nil })
        XCTAssertTrue(read(config.now).contains("- Tasks: 0 of 2 done"))
        XCTAssertTrue(read(config.inbox).hasPrefix("# PastelFocus Inbox"))
    }

    /// Regression: rewriting unchanged files woke the app's own file watcher in a loop (~20% CPU).
    func testOldEstimatesAndSessionCountsBecomeTimeSpentWithABackup() throws {
        let url = config.dailyNote("2026-10-06")
        write("- [x] Old work #career [est:: 3] [sessions:: 2] ✅ 2026-10-06 🆔 old1\n- [x] Logged work [sessions:: 1] 🆔 log1\n", to: url)
        // The log knows about 40 minutes on log1, which wins over its old count of one session.
        let s = SessionRecord(id: "s1", kind: .focus, taskId: "log1", taskTitle: "Logged work", category: nil, preset: "25/5",
                              plannedS: 2400, startedAt: clock.now().addingTimeInterval(-86_400), endedAt: clock.now().addingTimeInterval(-84_000),
                              tz: "Asia/Dubai", focusedS: 2400, outcome: .completed, pauses: [])
        try c.recorder.log.append(s, at: s.startedAt)
        c.refresh()
        XCTAssertEqual(SafeFile.readLines(url).prefix(2), [
            "- [x] Old work #career [spent:: 50m] ✅ 2026-10-06 🆔 old1",
            "- [x] Logged work [spent:: 40m] 🆔 log1",
        ])
        XCTAssertFalse(read(config.dailyNote("2026-10-07")).contains("[est::"))
        let backups = try FileManager.default.contentsOfDirectory(atPath: support.appendingPathComponent("Backups").path)
        XCTAssertEqual(backups.count, 1)
        let saved = support.appendingPathComponent("Backups/\(backups[0])/\(config.relativePath(url))")
        XCTAssertTrue(read(saved).contains("[est:: 3] [sessions:: 2]"))
    }

    func testRefreshDoesNotRewriteUnchangedFiles() throws {
        c.refresh()
        let mtime = { (try? FileManager.default.attributesOfItem(atPath: self.config.now.path)[.modificationDate]) as? Date }
        let before = mtime()
        Thread.sleep(forTimeInterval: 1.1)
        clock.advance(120) // even the "Updated" minute changes
        c.refresh()
        XCTAssertEqual(mtime(), before)
    }

    func testOutsideEditIsLoggedOnceAndAppEditsAreNotDoubled() throws {
        c.refresh()
        // You tick a task in Obsidian.
        let url = config.dailyNote("2026-10-07")
        write(read(url).replacingOccurrences(of: "- [ ] Finalize resume", with: "- [x] Finalize resume"), to: url)
        let external = c.refresh()
        XCTAssertEqual(external.map(\.type), [.completed])
        XCTAssertEqual(external.first?.actor, .external)
        // The app reopens it: logged once, as the app's own change.
        try c.perform { try $0.setStatus("r7q2", .todo, actor: .you) }
        XCTAssertTrue(c.refresh().isEmpty)
        XCTAssertEqual(c.store.events.readAll().map(\.actor), [.external, .you])
    }

    func testHermesInboxRoundTrip() {
        c.refresh()
        write(read(config.inbox) + "- [ ] complete 🆔 r7q2\n", to: config.inbox)
        c.refresh()
        XCTAssertEqual(c.store.find("r7q2")?.status, .done)
        XCTAssertTrue(read(config.now).contains("- Tasks: 1 of 2 done"))
        XCTAssertEqual(c.store.events.readAll().last?.actor, .hermes)
    }

    func testFocusSessionFlowAndRestore() throws {
        c.refresh()
        try c.startFocus(task: c.store.find("r7q2"))
        XCTAssertEqual(c.store.find("r7q2")?.status, .inProgress)
        XCTAssertTrue(read(config.now).contains("focusing on \"Finalize resume\""))
        XCTAssertNotNil(c.engine.countdownEnd)

        // App restarts mid-session.
        clock.advance(600)
        let c2 = Coordinator(config: config, calendar: dubai, clock: clock, supportDir: support)
        XCTAssertEqual(c2.engine.focusedS, 600)
        clock.advance(900)
        let record = try XCTUnwrap(c2.tick())
        c2.sessionEnded(record)
        XCTAssertEqual(c2.store.find("r7q2")?.spentMinutes, 25)
        XCTAssertTrue(read(config.dailyNote("2026-10-07")).contains("## Focus log"))
    }

    func testNightlyWritesStatsInsightsSummaryAndIndex() throws {
        c.refresh()
        try c.startFocus(task: c.store.find("r7q2"))
        clock.advance(1500)
        c.sessionEnded(try XCTUnwrap(c.tick()))
        try c.nightly()
        XCTAssertTrue(read(config.insights).contains("**Still learning.** 1 focus sessions logged since 2026-10-07."))
        XCTAssertTrue(read(config.statsDir.appendingPathComponent("2026-W41.md")).contains("| Focused time | 25 min |"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: config.statsDir.appendingPathComponent("2026-10.md").path))
        let note = read(config.dailyNote("2026-10-07"))
        XCTAssertTrue(note.contains("## PastelFocus summary"))
        XCTAssertTrue(note.contains("- Focused: 25 min · 1 finished, 0 interrupted"))
        // Running twice replaces the section instead of adding another.
        try c.nightly()
        XCTAssertEqual(read(config.dailyNote("2026-10-07")).components(separatedBy: "## PastelFocus summary").count, 2)
        XCTAssertEqual(c.index?.count("sessions"), 1)
        XCTAssertEqual(c.index?.completedSessions(forTask: "r7q2"), 1)
    }

    /// Regression for the mismatch Hermes reported: Now.md said 2 of 9 while the note's summary said 1 of 8.
    func testNowAndNoteSummaryAlwaysAgree() throws {
        c.refresh()
        try c.nightly() // writes the summary in the morning
        // During the day: a task is ticked in Obsidian, Hermes adds one, and one is ticked in the panel.
        let url = config.dailyNote("2026-10-07")
        write(read(url).replacingOccurrences(of: "- [ ] Legacy line", with: "- [x] Legacy line"), to: url)
        c.refresh()
        write(read(config.inbox) + "- [ ] create Add career samples #career\n", to: config.inbox)
        c.refresh()
        try c.perform { try $0.setStatus("r7q2", .done, actor: .you) }

        func count(_ text: String) -> String? {
            text.range(of: #"- Tasks: \d+ of \d+ done"#, options: .regularExpression).map { String(text[$0]) }
        }
        let now = count(read(config.now)), note = count(read(url))
        XCTAssertEqual(now, "- Tasks: 2 of 3 done")
        XCTAssertEqual(note, now, "the note's summary must match Now.md without waiting for the nightly pass")
        XCTAssertEqual(c.todayTotals().done, 2)
        // Only one summary section, even after many updates.
        XCTAssertEqual(read(url).components(separatedBy: "## PastelFocus summary").count, 2)
    }

    func testSummaryIsNotRewrittenWhenNothingChanged() throws {
        c.refresh()
        let url = config.dailyNote("2026-10-07")
        let mtime = { (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date }
        let before = mtime()
        Thread.sleep(forTimeInterval: 1.1)
        c.writeNow()
        c.refresh()
        XCTAssertEqual(mtime(), before)
    }

    func testIndexRebuildsFromScratch() throws {
        c.refresh()
        try c.nightly()
        let tasks = c.tasks, events = c.store.events.readAll()
        c = nil // the app has quit; you delete the cache
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: support.appendingPathComponent("index.sqlite" + suffix))
        }
        let db = try IndexDatabase(url: support.appendingPathComponent("index.sqlite"))
        XCTAssertEqual(db.count("tasks"), 0)
        try db.rebuild(tasks: tasks, sessions: [], events: events, insights: [])
        XCTAssertEqual(db.count("tasks"), 2)
    }
}
