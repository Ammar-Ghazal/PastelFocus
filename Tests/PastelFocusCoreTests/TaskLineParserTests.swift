import XCTest
@testable import PastelFocusCore

final class TaskLineParserTests: XCTestCase {
    func testParsesTasksPluginFields() throws {
        let line = "- [ ] Finalize resume — one ready-to-send version #career ⏫ [spent:: 1h 25m] ➕ 2026-10-05 ⏳ 2026-10-07 📅 2026-10-10 🆔 r7q2"
        let t = try XCTUnwrap(TaskLineParser.parse(line))
        XCTAssertEqual(t.taskID, "r7q2")
        XCTAssertEqual(t.status, .todo)
        XCTAssertEqual(t.priority, .high)
        XCTAssertEqual(t.spentMinutes, 85)
        XCTAssertFalse(t.hasLegacyTimeFields)
        XCTAssertEqual(t.created, "2026-10-05")
        XCTAssertEqual(t.scheduled, "2026-10-07")
        XCTAssertEqual(t.due, "2026-10-10")
        XCTAssertEqual(t.title, "Finalize resume")
        XCTAssertEqual(t.subtitle, "one ready-to-send version")
        XCTAssertEqual(t.category, "career")
    }

    func testRoundTripIsStable() throws {
        let line = "- [x] LeetCode: 2 new + 2 review #learning [spent:: 2h] 🔼 ➕ 2026-10-07 ✅ 2026-10-07 🆔 k3m9"
        let t = try XCTUnwrap(TaskLineParser.parse(line))
        XCTAssertEqual(TaskLineParser.serialize(t), line)
        XCTAssertEqual(t.status, .done)
        XCTAssertEqual(t.completed, "2026-10-07")
    }

    func testSpentAcceptsSeveralSpellings() {
        for (text, minutes) in [("1h 25m", 85), ("1h25m", 85), ("2h", 120), ("45m", 45), ("45 min", 45), ("45", 45)] {
            XCTAssertEqual(TaskLineParser.parseMinutes(text), minutes, text)
        }
        XCTAssertNil(TaskLineParser.parseMinutes("soon"))
        XCTAssertEqual([25, 60, 85].map(TaskLineParser.formatMinutes), ["25m", "1h", "1h 25m"])
    }

    func testOldSessionFieldsAreReadButBecomeTime() throws {
        let t = try XCTUnwrap(TaskLineParser.parse("- [ ] Resume #career [est:: 3] [sessions:: 2] 🆔 r7q2"))
        XCTAssertEqual(t.legacyEstimate, 3)
        XCTAssertEqual(t.legacySessions, 2)
        XCTAssertTrue(t.hasLegacyTimeFields)
        XCTAssertEqual(t.title, "Resume")
        // Written back, the estimate goes and the count is kept as time (2 × 25 min).
        XCTAssertEqual(TaskLineParser.serialize(t), "- [ ] Resume #career [spent:: 50m] 🆔 r7q2")
    }

    func testRecurrenceIsReadAndKept() throws {
        let t = try XCTUnwrap(TaskLineParser.parse("- [ ] Stretch 🔁 every week on Monday, Friday #health ⏳ 2026-10-08 🆔 st01"))
        XCTAssertEqual(t.recurrence, "every week on Monday, Friday")
        XCTAssertTrue(t.isRepeating)
        XCTAssertEqual(t.title, "Stretch")
        XCTAssertEqual(t.tags, ["health"])
        XCTAssertEqual(TaskLineParser.serialize(t), "- [ ] Stretch #health 🔁 every week on Monday, Friday ⏳ 2026-10-08 🆔 st01")
        XCTAssertFalse(try XCTUnwrap(TaskLineParser.parse("- [ ] Once 🆔 on01")).isRepeating)
    }

    func testLegacyHermesLine() throws {
        let line = "- [ ] **P1 · 90 min** Finalize resume — make one accurate version. **In progress as of about 13:10.**"
        let t = try XCTUnwrap(TaskLineParser.parse(line))
        XCTAssertEqual(t.priority, .high)
        XCTAssertTrue(t.priorityFromLegacy)
        XCTAssertEqual(t.title, "Finalize resume")
        // Stamping an ID keeps the legacy marker and does not add a duplicate priority emoji.
        var stamped = t
        stamped.taskID = "abcd"
        let out = TaskLineParser.serialize(stamped)
        XCTAssertTrue(out.hasPrefix("- [ ] **P1 · 90 min** Finalize resume"))
        XCTAssertFalse(out.contains("⏫"))
        XCTAssertTrue(out.hasSuffix("In progress as of about 13:10.** 🆔 abcd"))
    }

    func testLegacyHourRange() throws {
        let t = try XCTUnwrap(TaskLineParser.parse("- [x] **P1 · 1–2 h** LeetCode practice"))
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
