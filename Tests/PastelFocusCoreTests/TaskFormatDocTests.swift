import XCTest
@testable import PastelFocusCore

/// Keeps docs/TASK_FORMAT.md honest: its examples must mean what the page says they mean.
final class TaskFormatDocTests: XCTestCase {
    func doc() throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("docs/TASK_FORMAT.md"), encoding: .utf8)
    }

    func testExampleLineRoundTripsWithEveryField() throws {
        let line = try XCTUnwrap(doc().components(separatedBy: "\n").first { $0.hasPrefix("- [ ] 07:00 - 07:45 Job pipeline") })
        let t = try XCTUnwrap(TaskLineParser.parse(line))
        XCTAssertEqual(TaskLineParser.serialize(t), line, "the example is in the order the app writes")
        XCTAssertEqual(t.startTime, "07:00")
        XCTAssertEqual(t.durationMinutes, 45)
        XCTAssertEqual(t.title, "Job pipeline")
        XCTAssertEqual(t.subtitle, "scan and triage 25 leads")
        XCTAssertEqual(t.category, "career")
        XCTAssertEqual(t.spentMinutes, 25)
        XCTAssertEqual(t.progress, 40)
        XCTAssertEqual(t.priority, .high)
        XCTAssertEqual(t.rule, Recurrence(unit: .week, weekdays: [1, 2, 3, 4, 5]))
        XCTAssertEqual([t.created, t.scheduled, t.due], ["2026-10-08", "2026-10-09", "2026-10-10"])
        XCTAssertEqual(t.taskID, "zzwi")
    }

    func testEveryRepeatRuleInTheTableIsUnderstood() throws {
        let rules = ["every day", "every 3 days", "every week", "every 2 weeks", "biweekly", "every other week",
                     "every week on Monday, Thursday", "every 2 weeks on Friday", "every Tuesday and Friday",
                     "every weekday", "every weekend", "every month", "every 2 months", "every day when done"]
        let text = try doc()
        for r in rules {
            XCTAssertNotNil(Recurrence(r), r)
            XCTAssertTrue(text.contains("`\(r.replacingOccurrences(of: " when done", with: ""))`") || r.hasSuffix("when done"), "\(r) is documented")
        }
    }

    func testInboxExamplesParse() throws {
        let commands = try doc().components(separatedBy: "\n").filter { $0.hasPrefix("- [ ] ") && !$0.hasPrefix("- [ ] 07:00") }
            .flatMap { $0.dropFirst(6).components(separatedBy: " · ") }
            .filter { !$0.contains("|") }
        XCTAssertGreaterThanOrEqual(commands.count, 9)
        for c in commands { XCTAssertNoThrow(try InboxProcessor.parse(c), c) }
    }
}
