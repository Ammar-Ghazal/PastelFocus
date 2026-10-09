import XCTest
@testable import PastelFocusCore

final class AnalyticsTests: XCTestCase {
    let engine = AnalyticsEngine(calendar: dubai)
    let now = ISO8601.date("2026-10-31T18:00:00Z")!

    /// A focus session `daysAgo` days back at local hour `hour` (Dubai, UTC+4).
    func session(_ daysAgo: Int, hour: Int, minute: Int = 0, category: String? = "career", planned: Int = 25,
                 outcome: SessionOutcome = .completed, firstPauseMin: Int? = nil, focusedMin: Int? = nil,
                 kind: SessionKind = .focus, task: String? = nil) -> SessionRecord {
        let dayStart = Calendar(identifier: .gregorian).date(byAdding: .day, value: -daysAgo, to: ISO8601.date("2026-10-31T00:00:00Z")!)!
        let start = dayStart.addingTimeInterval(Double((hour - 4) * 3600 + minute * 60))
        let focused = (focusedMin ?? (outcome == .completed ? planned : planned / 2)) * 60
        return SessionRecord(id: "s\(UUID().uuidString.prefix(7))", kind: kind, taskId: task, taskTitle: nil, category: category,
                             preset: "25/5", plannedS: planned * 60, startedAt: start, endedAt: start.addingTimeInterval(Double(focused)),
                             tz: "Asia/Dubai", focusedS: focused, outcome: outcome,
                             pauses: firstPauseMin.map { [PauseRecord(atS: $0 * 60, durS: 60)] } ?? [])
    }

    func testWilsonInterval() {
        let w = wilson(5, 10, z: 1.96)
        XCTAssertEqual(w.low, 0.2366, accuracy: 0.001)
        XCTAssertEqual(w.high, 0.7634, accuracy: 0.001)
    }

    func testTooLittleDataGivesNoInsights() {
        let s = (0..<5).map { session($0, hour: 10, outcome: .stoppedEarly) }
        XCTAssertTrue(engine.insights(AnalyticsInput(sessions: s, events: [], tasks: []), now: now).isEmpty)
    }

    func testFocusSpanSuggestsShorterSessions() throws {
        let s = (0..<16).map { session($0, hour: 10, planned: 50, firstPauseMin: 38 + $0 % 8) }
        let ins = try XCTUnwrap(engine.insights(AnalyticsInput(sessions: s, events: [], tasks: []), now: now).first { $0.kind == "focus_span" })
        XCTAssertEqual(ins.sampleN, 16)
        XCTAssertEqual(ins.value, 41.5, accuracy: 0.01)
        XCTAssertTrue(ins.title.contains("try 40-min sessions"), ins.title)
        XCTAssertTrue(ins.evidence.contains("median of 42 min"), ins.evidence)
    }

    func testCategoryWithMoreInterruptions() throws {
        var s: [SessionRecord] = []
        for i in 0..<14 { s.append(session(i % 9, hour: 10 + i % 3, category: "coding", outcome: i < 10 ? .stoppedEarly : .completed)) }
        for i in 0..<20 { s.append(session(i % 9, hour: 10 + i % 3, category: "learning", outcome: i < 3 ? .stoppedEarly : .completed)) }
        let all = engine.insights(AnalyticsInput(sessions: s, events: [], tasks: []), now: now)
        let coding = try XCTUnwrap(all.first { $0.scope == "category:coding" })
        XCTAssertEqual(coding.title, "More interruptions in coding tasks")
        XCTAssertTrue(coding.evidence.contains("10 of 14 times (71%)"), coding.evidence)
    }

    func testSimilarRatesAreNotAPattern() {
        var s: [SessionRecord] = []
        for i in 0..<20 { s.append(session(i % 10, hour: 10, category: "coding", outcome: i % 4 == 0 ? .stoppedEarly : .completed)) }
        for i in 0..<20 { s.append(session(i % 10, hour: 10, category: "learning", outcome: i % 5 == 0 ? .stoppedEarly : .completed)) }
        XCTAssertFalse(engine.insights(AnalyticsInput(sessions: s, events: [], tasks: []), now: now).contains { $0.kind == "category" })
    }

    func testFatigueAfterThirdBlock() throws {
        var s: [SessionRecord] = []
        for d in 0..<10 {
            for n in 0..<5 {
                let late = n >= 3
                s.append(session(d, hour: 9 + n * 2, category: nil, outcome: late && (d % 5 != 0) ? .stoppedEarly : .completed))
            }
        }
        let ins = try XCTUnwrap(engine.insights(AnalyticsInput(sessions: s, events: [], tasks: []), now: now).first { $0.kind == "fatigue" })
        XCTAssertEqual(ins.scope, "session#4+")
        XCTAssertEqual(ins.title, "Focus drops from your 4th block of the day")
    }

    func testPostponedAndNoEstimateInsights() throws {
        let tasks = (0..<8).map { i in TaskItem(taskID: "t\(i)", status: .done, description: "Bug \(i) #coding") }
            + [TaskItem(taskID: "late", description: "Write cover letter #career")]
        var s: [SessionRecord] = []
        for i in 0..<8 { s += [session(i, hour: 10, category: "coding", task: "t\(i)"), session(i, hour: 12, category: "coding", task: "t\(i)")] }
        let events = (1...3).map { TaskEvent(at: now.addingTimeInterval(Double(-$0) * 86_400), taskId: "late", type: .rescheduled, actor: .you) }
        let all = engine.insights(AnalyticsInput(sessions: s, events: events, tasks: tasks), now: now)
        XCTAssertNil(all.first { $0.kind == "estimate" }) // estimates are gone
        XCTAssertEqual(all.first { $0.kind == "postponed" }?.title, "\"Write cover letter\" keeps getting postponed")
    }

    func testRollupsAndReports() {
        let s = [session(0, hour: 9), session(0, hour: 11, outcome: .stoppedEarly, focusedMin: 10),
                 session(0, hour: 12, category: nil, kind: .nsdr)]
        let events = [TaskEvent(at: s[0].endedAt, taskId: "a", type: .completed, actor: .you)]
        let r = Rollups.build(sessions: s, events: events, calendar: dubai)["2026-10-31"]!
        XCTAssertEqual(r.completed, 1)
        XCTAssertEqual(r.interrupted, 1)
        XCTAssertEqual(r.nsdr, 1)
        XCTAssertEqual(r.focusedS, 35 * 60)
        XCTAssertEqual(r.tasksDone, 1)
        XCTAssertFalse(r.isGoodDay())
        XCTAssertTrue(r.isGoodDay(minFocusedMinutes: 30))

        let md = Reports.stats(title: "Week 2026-W44", days: ["2026-10-31"], rollups: ["2026-10-31": r], sessions: s)
        XCTAssertTrue(md.contains("| Focused time | 35 min |"))
        XCTAssertTrue(md.contains("| Finish rate | 50% |"))
        XCTAssertTrue(md.contains("| Good days (3 h+ focused) | 0 of 1 |"))

        let empty = Reports.insights([], totalFocusSessions: 3, since: "2026-10-30", updated: now, calendar: dubai)
        XCTAssertTrue(empty.contains("**Still learning.** 3 focus sessions logged since 2026-10-30."))

        let nowMD = Reports.now(.init(appRunning: true, phase: .running, taskTitle: "Resume", taskID: "r7q2", kind: .focus, remainingS: 600, plannedS: 1500),
                                today: [TaskItem(taskID: "r7q2", description: "Resume", spentMinutes: 85)], rollup: r, updated: now, calendar: dubai)
        XCTAssertTrue(nowMD.contains("focusing on \"Resume\" (🆔 r7q2) — 10 min left of 25 min"))
        XCTAssertTrue(nowMD.contains("- Resume · 🆔 r7q2 · 1 h 25 min spent"))
    }
}
