import XCTest
@testable import PastelFocusCore

/// The shared wiki/report layout and the agent→Inbox→canonical task loop use a temporary vault.
final class CareerCoachContractTests: XCTestCase {
    func testActualHermesFixtureCommandsRoundTrip() throws {
        guard let path = ProcessInfo.processInfo.environment["PASTELFOCUS_COACH_FIXTURE"] else {
            throw XCTSkip("Run against the explicit disposable Hermes output fixture when available")
        }
        let source = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        XCTAssertTrue(source.path.contains("/review/coach-runs/") && source.lastPathComponent == "test-vault")
        guard source.path.contains("/review/coach-runs/"), source.lastPathComponent == "test-vault" else { return }
        // Work on a copy: refresh rewrites the Inbox, Now.md and the summary, and the run must stay as recorded.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("coach-fixture-\(UUID().uuidString)/test-vault")
        try FileManager.default.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: root)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let config = VaultConfig(root: root, privateLogs: root.appendingPathComponent(".private-logs"))
        let clock = FixedClock("2026-10-07T05:00:00Z")
        let coordinator = Coordinator(config: config, calendar: dubai, clock: clock,
                                      supportDir: root.appendingPathComponent(".support"))
        let rawInbox = read(config.inbox)
        XCTAssertTrue(rawInbox.contains("- [x] priority 🆔 fixture1 medium → applied 08:00 by hermes"))
        let pending = rawInbox.components(separatedBy: "\n").filter { $0.hasPrefix("- [ ] ") }
        XCTAssertEqual(pending.count, 2)
        let parsed = try pending.map { try InboxProcessor.parse(String($0.dropFirst(6))) }
        XCTAssertEqual(parsed.filter { if case .reschedule = $0.command { return true }; return false }.count, 1)
        XCTAssertEqual(parsed.filter { if case .create = $0.command { return true }; return false }.count, 1)
        coordinator.refresh()
        let tasks = coordinator.store.scan().tasks
        XCTAssertEqual(tasks.count, 2, "Only canonical tasks enter the app; report previews are excluded")
        let existing = try XCTUnwrap(coordinator.store.find("fixture1"))
        XCTAssertEqual(existing.scheduled, "2026-10-09")
        // The old session count became time spent (one session, no log: 25 min); the estimate went.
        XCTAssertEqual(existing.spentMinutes, 25)
        XCTAssertFalse(existing.hasLegacyTimeFields)
        let made = try XCTUnwrap(tasks.first { $0.description == "Synthetic parser diagnostic #coding" })
        XCTAssertNotNil(made.taskID)
        XCTAssertEqual(made.scheduled, "2026-10-08")
        XCTAssertEqual(made.created, "2026-10-07")
        XCTAssertFalse(made.hasLegacyTimeFields, "an estimate in a create command is dropped")
        XCTAssertEqual(made.priority, .high)
        XCTAssertTrue(read(config.inbox).contains("→ created 🆔 " + made.taskID!))
        XCTAssertFalse(read(config.inbox).contains("→ error:"))
        // After refresh: the Focus log is kept, and the app replaces its own summary with real totals
        // that match Now.md (one section, not appended).
        let note = read(config.dailyNote("2026-10-07"))
        XCTAssertTrue(note.contains("App-owned synthetic log: preserve."))
        XCTAssertTrue(note.contains("- [ ] Synthetic existing deliverable"), "task lines are kept")
        XCTAssertEqual(note.components(separatedBy: "## PastelFocus summary").count, 2)
        XCTAssertFalse(note.contains("App-owned synthetic totals: preserve."), "the app-owned summary is regenerated")
        func tasksLine(_ text: String) -> String? {
            text.range(of: #"- Tasks: \d+ of \d+ done"#, options: .regularExpression).map { String(text[$0]) }
        }
        XCTAssertNotNil(tasksLine(note))
        XCTAssertEqual(tasksLine(note), tasksLine(read(config.now)))
        XCTAssertTrue(read(config.now).contains("# Now"))
        XCTAssertTrue(coordinator.refresh().isEmpty)
        XCTAssertEqual(coordinator.store.scan().tasks.count, 2, "Repeated refresh cannot replay consumed commands")
    }

    func testWikiAndReportChecklistsDoNotEnterTaskIndex() throws {
        let config = makeVault()
        defer { try? FileManager.default.removeItem(at: config.root) }
        let clock = FixedClock("2026-10-07T05:00:00Z")
        let store = TaskStore(config: config, calendar: dubai, clock: clock)
        write("## Today's task list\n\n- [ ] Approved deliverable #coding [est:: 2] [sessions:: 1] ⏳ 2026-10-07 🆔 stable1\n\n## Career planning note\n\n1. Proposed experiment — needs approval.\n", to: config.dailyNote("2026-10-07"))
        for path in ["Learning Library/Career/wiki/concepts/example.md", "Learning Library/Career/raw/example.md", "Learning Library/Career/Reports/Daily/2026-10-07.md", "Learning Library/Career/Reports/Weekly/2026-W41.md", "Learning Library/Career/Reports/Monthly/2026-10.md", "Learning Library/Career/Weekly Plans/2026-W42.md"] {
            write("# Knowledge or draft report\n\n- [ ] This must never become a live task\n", to: config.root.appendingPathComponent(path))
        }
        let scan = store.scan()
        XCTAssertEqual(scan.tasks.map(\.taskID), ["stable1"])
        XCTAssertTrue(scan.problems.isEmpty)
        XCTAssertEqual(try store.stampMissingIDs(), 0)
        XCTAssertFalse(read(config.root.appendingPathComponent("Learning Library/Career/wiki/concepts/example.md")).contains("🆔"))
    }

    func testInboxCreatesCanonicalTaskAndPreservesExistingData() throws {
        let config = makeVault()
        defer { try? FileManager.default.removeItem(at: config.root) }
        let clock = FixedClock("2026-10-07T05:00:00Z")
        let store = TaskStore(config: config, calendar: dubai, clock: clock)
        let inbox = InboxProcessor(store: store, calendar: dubai, clock: clock)
        let existing = "- [x] Existing deliverable #career [est:: 3] [sessions:: 2] ✅ 2026-10-07 🆔 keep1"
        let generated = "## Focus log\n\nApp-owned log.\n\n## PastelFocus summary\n\nApp-owned totals.\n"
        write("## Today's task list\n\n" + existing + "\n\n" + generated, to: config.dailyNote("2026-10-07"))
        write("# Now\n\nApp-owned running timer and totals.\n", to: config.now)
        write("# Insights\n\nApp-owned evidence.\n", to: config.insights)
        let now = read(config.now), insights = read(config.insights)
        let historical = "- [x] priority 🆔 keep1 high → applied 08:00 by hermes"
        write("# PastelFocus Inbox\n\n## Commands\n\n" + historical + "\n- [ ] create Implement parser diagnostic #coding [est:: 2] ⏫ ➕ 2026-10-07 ⏳ 2026-10-08 — reason: approved task\n", to: config.inbox)
        XCTAssertEqual(try inbox.process(), 1)
        let created = try XCTUnwrap(store.scan().tasks.first { $0.description.contains("Implement parser diagnostic") })
        XCTAssertNotNil(created.taskID)
        XCTAssertEqual(created.scheduled, "2026-10-08")
        XCTAssertFalse(created.hasLegacyTimeFields)
        XCTAssertNil(created.spentMinutes)
        XCTAssertEqual(created.priority, .high)
        XCTAssertTrue(read(config.inbox).contains("→ created 🆔 " + created.taskID!))
        XCTAssertTrue(read(config.inbox).contains(historical))
        XCTAssertTrue(read(config.dailyNote("2026-10-07")).contains(existing))
        XCTAssertTrue(read(config.dailyNote("2026-10-07")).contains(generated))
        XCTAssertEqual(read(config.now), now)
        XCTAssertEqual(read(config.insights), insights)
        XCTAssertEqual(try inbox.process(), 0, "A consumed command cannot create a second task")

        let id = created.taskID!
        write(read(config.inbox) + "- [ ] reschedule 🆔 \(id) ⏳ 2026-10-09 — reason: approved adjustment\n", to: config.inbox)
        XCTAssertEqual(try inbox.process(), 1)
        XCTAssertEqual(store.find(id)?.scheduled, "2026-10-09")
        XCTAssertEqual(store.scan().tasks.count, 2, "Rescheduling preserves identity instead of copying")
    }
}
