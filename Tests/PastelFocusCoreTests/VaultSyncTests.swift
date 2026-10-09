import XCTest
@testable import PastelFocusCore

final class VaultSyncTests: XCTestCase {
    var config: VaultConfig!
    var clock: FixedClock!
    var c: Coordinator!

    override func setUp() {
        config = makeVault()
        clock = FixedClock("2026-10-07T05:00:00Z")
        write("## Today's task list\n\n- [ ] Finalize resume #career 🆔 r7q2\n", to: config.dailyNote("2026-10-07"))
        c = Coordinator(config: config, calendar: dubai, clock: clock, supportDir: config.root.appendingPathComponent(".support"))
        c.refresh()
    }

    func testOnlyTaskFilesCount() {
        XCTAssertTrue(config.isTaskSource(config.dailyNote("2026-10-07").path))
        XCTAssertTrue(config.isTaskSource(config.backlog.path))
        XCTAssertTrue(config.isTaskSource(config.inbox.path))
        XCTAssertTrue(config.isTaskSource(config.tags.path))
        for ignored in [config.now, config.insights, config.problems, config.statsDir.appendingPathComponent("2026-W41.md"),
                        config.logsDir.appendingPathComponent("events-2026-10.jsonl"),
                        config.dailyDir.appendingPathComponent(".2026-10-07.md.pf-1234.tmp"),
                        config.dailyDir.appendingPathComponent("Archive/2026-01-01.md"),
                        config.root.appendingPathComponent("LLM Wiki/Career/wiki/page.md")] {
            XCTAssertFalse(config.isTaskSource(ignored.path), ignored.lastPathComponent)
        }
    }

    func testAppWritesAreNotMistakenForOutsideChanges() throws {
        XCTAssertNil(c.externalChange(), "nothing changed since the first refresh")
        try c.perform { try $0.setStatus("r7q2", .done, actor: .you) }
        XCTAssertNil(c.externalChange(), "the app's own edit is already known")
        c.refresh()
        XCTAssertNil(c.externalChange(), "refresh's own writes (Now.md, ticks) are known too")
    }

    func testOutsideEditIsSeenWithItsTime() throws {
        Thread.sleep(forTimeInterval: 0.02)
        let url = config.dailyNote("2026-10-07")
        write(read(url) + "- [ ] Added in Obsidian\n", to: url)
        let change = try XCTUnwrap(c.externalChange())
        XCTAssertEqual(change.paths, [url.standardizedFileURL.path])
        XCTAssertNotNil(change.newest)
        c.refresh()
        XCTAssertNil(c.externalChange())
        XCTAssertTrue(c.tasks.contains { $0.title == "Added in Obsidian" })
    }

    func testNewAndDeletedFilesCount() throws {
        write("- [ ] Planned ahead\n", to: config.dailyNote("2026-10-09"))
        XCTAssertNotNil(c.externalChange())
        c.refresh()
        try FileManager.default.removeItem(at: config.dailyNote("2026-10-09"))
        let gone = try XCTUnwrap(c.externalChange())
        XCTAssertNil(gone.newest)
    }

    func testLatencyPercentiles() {
        var l = SyncLatency(capacity: 5)
        XCTAssertNil(l.p95)
        for s in [0.2, 0.3, 0.25, 0.9, 0.35, 0.4] { l.record(s) }
        XCTAssertEqual(l.samples, [0.3, 0.25, 0.9, 0.35, 0.4], "keeps the last five")
        XCTAssertEqual(l.p50, 0.35)
        XCTAssertEqual(l.p95, 0.9)
        XCTAssertEqual(l.last, 0.4)
    }
}
