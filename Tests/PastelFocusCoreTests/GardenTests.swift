import XCTest
@testable import PastelFocusCore

final class GardenTests: XCTestCase {
    let now = ISO8601.date("2026-10-31T18:00:00Z")!

    func focus(_ id: String, day: Int, minutes: Int = 25, category: String? = "learning", outcome: SessionOutcome = .completed,
               paused: Bool = false, task: String? = nil, kind: SessionKind = .focus) -> SessionRecord {
        let start = ISO8601.date(String(format: "2026-10-%02dT06:00:00Z", day))!
        return SessionRecord(id: id, kind: kind, taskId: task, taskTitle: nil, category: category, preset: "25/5",
                             plannedS: minutes * 60, startedAt: start, endedAt: start.addingTimeInterval(Double(minutes * 60)),
                             tz: "Asia/Dubai", focusedS: minutes * 60, outcome: outcome,
                             pauses: paused ? [PauseRecord(atS: 60, durS: 30)] : [])
    }

    func testGrowthRules() {
        let ev = (1...3).map { TaskEvent(at: ISO8601.date("2026-10-0\($0)T06:00:00Z")!, taskId: "hard", type: .rescheduled, actor: .you) }
        let s = [focus("a", day: 20, minutes: 15), focus("b", day: 20, minutes: 45), focus("c", day: 20, minutes: 45, paused: true),
                 focus("d", day: 21, minutes: 80, category: "coding", paused: true, task: "hard"),
                 focus("e", day: 31, outcome: .stoppedEarly), focus("f", day: 22, outcome: .stoppedEarly),
                 focus("g", day: 22, kind: .nsdr)]
        let g = GardenBuilder.build(sessions: s, events: ev, calendar: dubai, now: now)
        let items = Dictionary(uniqueKeysWithValues: g.islands.flatMap(\.items).map { ($0.id, $0) })
        XCTAssertEqual(items["a"]?.size, .sprout)
        XCTAssertEqual(items["b"]?.variant, .glowing)
        XCTAssertEqual(items["c"]?.variant, .normal)
        XCTAssertEqual(items["d"]?.variant, .golden)
        XCTAssertEqual(items["d"]?.species, .crystalPine)
        XCTAssertEqual(items["d"]?.size, .large)
        XCTAssertEqual(items["e"]?.kind, .wilted, "stopped within the last day")
        XCTAssertEqual(items["f"]?.kind, .richSoil, "older wilted sprouts become soil")
        XCTAssertEqual(items["g"]?.kind, .sleepingCat)
    }

    func testLayoutIsStableAndNonOverlapping() {
        let s = (0..<40).map { focus("s\($0)", day: 26 + $0 % 5) }
        let a = GardenBuilder.build(sessions: s, events: [], calendar: dubai, now: now)
        let b = GardenBuilder.build(sessions: s.shuffled(), events: [], calendar: dubai, now: now)
        XCTAssertEqual(a, b)
        for island in a.islands {
            let cells = island.items.map { "\($0.x),\($0.y)" }
            XCTAssertEqual(Set(cells).count, cells.count)
        }
    }

    func testLandmarksUnlockWithGoodDaysAndRunAllowsOneMissPerWeek() {
        // Good days Oct 19–25 except a single miss on Oct 22 (same ISO week).
        var s: [SessionRecord] = []
        for d in [19, 20, 21, 23, 24, 25] { s += [focus("x\(d)a", day: d), focus("x\(d)b", day: d)] }
        let g = GardenBuilder.build(sessions: s, events: [], calendar: dubai, now: ISO8601.date("2026-10-25T18:00:00Z")!)
        XCTAssertEqual(g.goodDays, 6)
        XCTAssertEqual(g.currentRun, 6)
        XCTAssertEqual(g.landmarks, [.path, .pond])
        // Two more misses in the next week end the run, but good days (and landmarks) remain.
        let later = GardenBuilder.build(sessions: s, events: [], calendar: dubai, now: ISO8601.date("2026-10-28T18:00:00Z")!)
        XCTAssertEqual(later.currentRun, 0)
        XCTAssertEqual(later.landmarks, [.path, .pond])
    }

    func testFirefliesCountFinishedTasks() {
        let ev = [TaskEvent(at: now, taskId: "a", type: .completed, actor: .you), TaskEvent(at: now, taskId: "b", type: .completed, actor: .hermes)]
        let g = GardenBuilder.build(sessions: [], events: ev, calendar: dubai, now: now)
        XCTAssertEqual(g.islands.first?.fireflies, 2)
    }

    func testStableHashDoesNotChangeBetweenRuns() {
        XCTAssertEqual(stableHash(""), 0xcbf29ce484222325)
        var r1 = SeededRandom(seed: 42), r2 = SeededRandom(seed: 42)
        XCTAssertEqual(r1.next(), r2.next())
        XCTAssertEqual(stableHash("abc"), 0xe71fa2190541574b)
    }
}
