import XCTest
@testable import PastelFocusCore

final class TaskLineParserTests: XCTestCase {
    func testParsesTasksPluginFields() throws {
        let line = "- [ ] Finalize resume — one ready-to-send version #career ⏫ [est:: 3] [sessions:: 1] ➕ 2026-10-05 ⏳ 2026-10-07 📅 2026-10-10 🆔 r7q2"
        let t = try XCTUnwrap(TaskLineParser.parse(line))
        XCTAssertEqual(t.taskID, "r7q2")
        XCTAssertEqual(t.status, .todo)
        XCTAssertEqual(t.priority, .high)
        XCTAssertEqual(t.estimateSessions, 3)
        XCTAssertEqual(t.actualSessions, 1)
        XCTAssertEqual(t.created, "2026-10-05")
        XCTAssertEqual(t.scheduled, "2026-10-07")
        XCTAssertEqual(t.due, "2026-10-10")
        XCTAssertEqual(t.title, "Finalize resume")
        XCTAssertEqual(t.subtitle, "one ready-to-send version")
        XCTAssertEqual(t.category, "career")
    }

    func testRoundTripIsStable() throws {
        let line = "- [x] LeetCode: 2 new + 2 review #learning [est:: 4] [sessions:: 4] 🔼 ➕ 2026-10-07 ✅ 2026-10-07 🆔 k3m9"
        let t = try XCTUnwrap(TaskLineParser.parse(line))
        XCTAssertEqual(TaskLineParser.serialize(t), line)
        XCTAssertEqual(t.status, .done)
        XCTAssertEqual(t.completed, "2026-10-07")
    }

    func testLegacyHermesLine() throws {
        let line = "- [ ] **P1 · 90 min** Finalize resume — make one accurate version. **In progress as of about 13:10.**"
        let t = try XCTUnwrap(TaskLineParser.parse(line))
        XCTAssertEqual(t.priority, .high)
        XCTAssertTrue(t.priorityFromLegacy)
        XCTAssertEqual(t.estimateSessions, 4) // 90 min / 25 rounded up
        XCTAssertEqual(t.title, "Finalize resume")
        // Stamping an ID keeps the legacy marker and does not add a duplicate priority emoji.
        var stamped = t
        stamped.taskID = "abcd"
        let out = TaskLineParser.serialize(stamped)
        XCTAssertTrue(out.hasPrefix("- [ ] **P1 · 90 min** Finalize resume"))
        XCTAssertFalse(out.contains("⏫"))
        XCTAssertTrue(out.hasSuffix("[est:: 4] 🆔 abcd"))
    }

    func testLegacyHourRange() throws {
        let t = try XCTUnwrap(TaskLineParser.parse("- [x] **P1 · 1–2 h** LeetCode practice"))
        XCTAssertEqual(t.estimateSessions, 5) // 120 min / 25 rounded up
        XCTAssertEqual(t.status, .done)
    }

    func testNonTaskLinesAreIgnored() {
        XCTAssertNil(TaskLineParser.parse("- Energy, morning (1–5):"))
        XCTAssertNil(TaskLineParser.parse("## Today's task list"))
        XCTAssertNotNil(TaskLineParser.parse("  - [/] Half done 🆔 x1y2"))
    }

    func testIDsAreShortAndDistinct() {
        let ids = Set((0..<200).map { _ in TaskLineParser.newID() })
        XCTAssertGreaterThan(ids.count, 190)
        XCTAssertTrue(ids.allSatisfy { $0.count == 4 })
    }
}
