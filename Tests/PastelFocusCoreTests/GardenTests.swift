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
        let items = Dictionary(uniqueKeysWithValues: g.items.map { ($0.id, $0) })
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
        var s = (0..<40).map { focus("s\($0)", day: 26 + $0 % 5) }
        for d in 1...7 { s += [focus("g\(d)a", day: d, minutes: 90), focus("g\(d)b", day: d, minutes: 90)] } // 7 good days: 3 landmarks
        let a = GardenBuilder.build(sessions: s, events: [], calendar: dubai, now: now)
        let b = GardenBuilder.build(sessions: s.shuffled(), events: [], calendar: dubai, now: now)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.landmarks.count, 3)
        for period in GardenPeriod.allCases {
            let plot = a.plot(period, containing: "2026-10-28", calendar: dubai)
            XCTAssertEqual(plot, b.plot(period, containing: "2026-10-28", calendar: dubai), "\(period)")
            let tiles = plot.items.map { GardenTile(x: $0.x, y: $0.y) }
            XCTAssertEqual(Set(tiles).count, tiles.count, "\(period): no two items share a tile")
            XCTAssertTrue(Set(tiles).isDisjoint(with: plot.landmarks.flatMap { $0.tiles(side: plot.side) }), "\(period): landmarks stay clear")
            XCTAssertTrue(tiles.allSatisfy { (0..<plot.side).contains($0.x) && (0..<plot.side).contains($0.y) })
        }
    }

    /// Like Forest: the plot gets bigger (and the view zooms out) instead of getting crowded.
    func testPlotGrowsWithItems() {
        func plot(_ n: Int, _ period: GardenPeriod = .month) -> GardenPlot {
            let s = (0..<n).map { focus("p\($0)", day: 1 + $0 % 28) }
            return GardenBuilder.build(sessions: s, events: [], calendar: dubai, now: now).plot(period, containing: "2026-10-15", calendar: dubai)
        }
        XCTAssertEqual(plot(0).side, Garden.minSide)
        XCTAssertEqual(plot(3).side, Garden.minSide)
        var last = 0
        for n in [10, 30, 80, 200] {
            let p = plot(n)
            XCTAssertEqual(p.items.count, n, "every session is placed")
            XCTAssertGreaterThan(p.side, last)
            XCTAssertLessThanOrEqual(Double(n), Double(p.side * p.side) * 0.5, "never more than about half full")
            last = p.side
        }
        XCTAssertEqual(plot(80, .day).items.count, 3, "a day shows only that day's sessions")
    }

    /// As the plot grows (more sessions, landmarks unlocking), earlier plants stay near the same
    /// relative spot rather than being reshuffled.
    func testPlantsKeepTheirRelativeSpotAsThePlotGrows() {
        let early = (0..<6).map { focus("e\($0)", day: 1 + $0) }
        let later = (0..<60).map { focus("l\($0)", day: 8 + $0 % 20) }
        let small = GardenBuilder.build(sessions: early, events: [], calendar: dubai, now: now).plot(.month, containing: "2026-10-15", calendar: dubai)
        let big = GardenBuilder.build(sessions: early + later, events: [], calendar: dubai, now: now).plot(.month, containing: "2026-10-15", calendar: dubai)
        XCTAssertGreaterThan(big.side, small.side)
        func spot(_ p: GardenPlot, _ id: String) -> (Double, Double) {
            let i = p.items.first { $0.id == id }!
            return ((Double(i.x) + 0.5) / Double(p.side), (Double(i.y) + 0.5) / Double(p.side))
        }
        for e in early {
            let a = spot(small, e.id), b = spot(big, e.id)
            // Within one small-plot tile of where it was (fractions of the plot).
            XCTAssertLessThanOrEqual(hypot(a.0 - b.0, a.1 - b.1), 1.0 / Double(small.side) + 0.01, e.id)
        }
    }

    func testPeriodKeysAndShifts() {
        XCTAssertEqual(GardenPeriod.week.key(for: "2026-10-07", calendar: dubai), "2026-W41")
        XCTAssertEqual(GardenPeriod.month.key(for: "2026-10-07", calendar: dubai), "2026-10")
        XCTAssertEqual(GardenPeriod.day.shift("2026-10-01", by: -1, calendar: dubai), "2026-09-30")
        XCTAssertEqual(GardenPeriod.week.shift("2026-10-07", by: -1, calendar: dubai), "2026-09-30")
        XCTAssertEqual(GardenPeriod.month.shift("2026-01-20", by: -1, calendar: dubai), "2025-12-01")
        XCTAssertEqual(GardenPeriod.month.shift("2026-12-05", by: 1, calendar: dubai), "2027-01-01")
    }

    func testLandmarksUnlockWithGoodDaysAndRunAllowsOneMissPerWeek() {
        // Good days Oct 19–25 except a single miss on Oct 22 (same ISO week).
        var s: [SessionRecord] = []
        for d in [19, 20, 21, 23, 24, 25] { s += [focus("x\(d)a", day: d, minutes: 90), focus("x\(d)b", day: d, minutes: 90)] }
        let g = GardenBuilder.build(sessions: s, events: [], calendar: dubai, now: ISO8601.date("2026-10-25T18:00:00Z")!)
        XCTAssertEqual(g.goodDays, 6)
        XCTAssertEqual(g.currentRun, 6)
        XCTAssertEqual(g.landmarks, [.path, .pond])
        // Two more misses in the next week end the run, but good days (and landmarks) remain.
        let later = GardenBuilder.build(sessions: s, events: [], calendar: dubai, now: ISO8601.date("2026-10-28T18:00:00Z")!)
        XCTAssertEqual(later.currentRun, 0)
        XCTAssertEqual(later.landmarks, [.path, .pond])
    }

    /// A good day is total focused time over the threshold (3 h by default). Stopped sessions'
    /// focused time counts; breaks and NSDR neither count nor spoil the day.
    func testGoodDayIsTotalFocusedTimeOverTheThreshold() {
        let s = [focus("a1", day: 20, minutes: 90), focus("a2", day: 20, minutes: 90),            // 3 h exactly: good
                 focus("a3", day: 20, minutes: 30, kind: .longBreak), focus("a4", day: 20, kind: .nsdr),
                 focus("b1", day: 21, minutes: 170), focus("b2", day: 21, minutes: 15, outcome: .stoppedEarly), // 3 h 5 min: good
                 focus("c1", day: 22, minutes: 25), focus("c2", day: 22, minutes: 25),            // two finished, 50 min: not good
                 focus("d1", day: 23, minutes: 120), focus("d2", day: 23, minutes: 200, kind: .longBreak)] // breaks add nothing
        let at = ISO8601.date("2026-10-23T18:00:00Z")!
        let byDefault = GardenBuilder.build(sessions: s, events: [], calendar: dubai, now: at)
        XCTAssertEqual(byDefault.goodDays, 2)
        let lower = GardenBuilder.build(sessions: s, events: [], calendar: dubai, now: at, goodDayMinutes: 45)
        XCTAssertEqual(lower.goodDays, 4)
        XCTAssertEqual(GoodDay.label(180), "3 h")
        XCTAssertEqual(GoodDay.label(150), "2 h 30 min")
        XCTAssertEqual(GoodDay.label(45), "45 min")
    }

    func testFirefliesCountFinishedTasks() {
        let ev = [TaskEvent(at: now, taskId: "a", type: .completed, actor: .you), TaskEvent(at: now, taskId: "b", type: .completed, actor: .hermes)]
        let g = GardenBuilder.build(sessions: [], events: ev, calendar: dubai, now: now)
        XCTAssertEqual(g.plot(.day, containing: "2026-10-31", calendar: dubai).fireflies, 2)
        XCTAssertEqual(g.plot(.day, containing: "2026-10-30", calendar: dubai).fireflies, 0)
    }

    func testStableHashDoesNotChangeBetweenRuns() {
        XCTAssertEqual(stableHash(""), 0xcbf29ce484222325)
        var r1 = SeededRandom(seed: 42), r2 = SeededRandom(seed: 42)
        XCTAssertEqual(r1.next(), r2.next())
        XCTAssertEqual(stableHash("abc"), 0xe71fa2190541574b)
    }
}
