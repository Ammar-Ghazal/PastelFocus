import XCTest
@testable import PastelFocusCore

final class StopReasonsTests: XCTestCase {
    func testShortReasonsAreTidiedNotCut() {
        XCTAssertEqual(StopReasons.shorten("  Phone   call. "), "phone call")
        XCTAssertEqual(StopReasons.shorten("Meeting"), "meeting")
        XCTAssertEqual(StopReasons.shorten("PR review"), "PR review", "keeps acronyms")
    }

    func testLongReasonsAreCutAtAWordWithEllipsis() {
        let s = StopReasons.shorten("Had to pick up my brother from school early today")
        XCTAssertEqual(s, "had to pick up my…")
        XCTAssertLessThanOrEqual(s.count, StopReasons.maxLength)
        let noSpaces = StopReasons.shorten("Supercalifragilisticexpialidocious")
        XCTAssertEqual(noSpaces.count, StopReasons.maxLength)
        XCTAssertTrue(noSpaces.hasSuffix("…"))
    }

    func testSavingDedupesCapsAndSkipsBuiltIns() {
        var saved: [String] = []
        saved = StopReasons.saving("Phone call", to: saved)
        saved = StopReasons.saving("phone call.", to: saved)
        XCTAssertEqual(saved, ["phone call"])
        XCTAssertEqual(StopReasons.saving("Interrupted", to: saved), saved)
        XCTAssertEqual(StopReasons.saving("   ", to: saved), saved)
        for i in 1...8 { saved = StopReasons.saving("reason \(i)", to: saved) }
        XCTAssertEqual(saved.count, StopReasons.maxSaved)
        XCTAssertEqual(saved.first, "reason 8")
    }

    func testFocusLogShowsShortReasonWhileJSONKeepsFullText() throws {
        let full = "Had to pick up my brother from school early today"
        let start = ISO8601.date("2026-10-07T06:00:00Z")!
        let r = SessionRecord(id: "s1234567", kind: .focus, taskId: "a1b2", taskTitle: "Resume", category: nil, preset: "25/5",
                              plannedS: 1500, startedAt: start, endedAt: start.addingTimeInterval(600), tz: "Asia/Dubai",
                              focusedS: 600, outcome: .stoppedEarly, stopReason: full)
        let line = SessionRecorder.focusLogLine(r, calendar: dubai)
        XCTAssertTrue(line.contains("stopped early (had to pick up my…)"), line)
        XCTAssertEqual(r.stopReason, full)
    }
}
