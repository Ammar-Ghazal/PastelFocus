import XCTest
@testable import PastelFocusCore

/// End-to-end flows against a temp vault: what the app does when files change, the timer ends, or night falls.
final class CoordinatorTests: XCTestCase {
    var config: VaultConfig!
    var clock: FixedClock!
    var support: URL!
    var widgets: URL!
    var c: Coordinator!

    override func setUp() {
        config = makeVault()
        clock = FixedClock("2026-10-07T05:00:00Z")
        support = config.root.appendingPathComponent(".support")
        widgets = config.root.appendingPathComponent(".group")
        write("## Today's task list\n\n- [ ] Finalize resume #career ⏫ [est:: 2] 🆔 r7q2\n- [ ] Legacy line\n", to: config.dailyNote("2026-10-07"))
        c = Coordinator(config: config, calendar: dubai, clock: clock, supportDir: support, widgetDir: widgets)
    }

    func testFirstRefreshStampsIDsAndWritesGeneratedFiles() {
        let external = c.refresh()
        XCTAssertTrue(external.isEmpty, "the first scan is a baseline, not a change")
        XCTAssertEqual(c.todayTasks.count, 2)
        XCTAssertTrue(c.todayTasks.allSatisfy { $0.taskID != nil })
        XCTAssertTrue(read(config.now).contains("- Tasks: 0 of 2 done"))
        XCTAssertTrue(read(config.inbox).hasPrefix("# PastelFocus Inbox"))
        XCTAssertEqual(WidgetBridge.read(from: widgets).totalCount, 2)
    }

    /// Regression: rewriting unchanged files woke the app's own file watcher in a loop (~20% CPU).
    func testRefreshDoesNotRewriteUnchangedFiles() throws {
        c.refresh()
        let mtime = { (try? FileManager.default.attributesOfItem(atPath: self.config.now.path)[.modificationDate]) as? Date }
        let snapshotTime = { (try? FileManager.default.attributesOfItem(atPath: WidgetBridge.snapshotURL(in: self.widgets).path)[.modificationDate]) as? Date }
        let before = mtime(), snapBefore = snapshotTime()
        Thread.sleep(forTimeInterval: 1.1)
        clock.advance(120) // even the "Updated" minute changes
        c.refresh()
        XCTAssertEqual(mtime(), before)
        XCTAssertEqual(snapshotTime(), snapBefore)
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
        XCTAssertNotNil(WidgetBridge.read(from: widgets).timerEnd)

        // App restarts mid-session.
        clock.advance(600)
        let c2 = Coordinator(config: config, calendar: dubai, clock: clock, supportDir: support, widgetDir: widgets)
        XCTAssertEqual(c2.engine.focusedS, 600)
        clock.advance(900)
        let record = try XCTUnwrap(c2.tick())
        c2.sessionEnded(record)
        XCTAssertEqual(c2.store.find("r7q2")?.actualSessions, 1)
        XCTAssertTrue(read(config.dailyNote("2026-10-07")).contains("## Focus log"))
    }

    func testWidgetTapsAreApplied() throws {
        c.refresh()
        try WidgetBridge.enqueue(WidgetCommand(action: .toggleTask, taskID: "r7q2", at: clock.now()), in: widgets)
        c.drainWidgetCommands()
        XCTAssertEqual(c.store.find("r7q2")?.status, .done)
        XCTAssertTrue(WidgetBridge.drain(in: widgets).isEmpty)
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
    func testNowNoteSummaryAndWidgetAlwaysAgree() throws {
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
        let w = WidgetBridge.read(from: widgets)
        XCTAssertEqual("- Tasks: \(w.doneCount) of \(w.totalCount) done", now)
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
