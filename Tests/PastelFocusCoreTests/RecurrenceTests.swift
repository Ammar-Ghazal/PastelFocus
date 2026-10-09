import XCTest
@testable import PastelFocusCore

final class RecurrenceTests: XCTestCase {
    // 2026-10-09 is a Friday.
    let cal = dubai

    func testReadsTheSupportedRules() {
        XCTAssertEqual(Recurrence("every day"), Recurrence(unit: .day))
        XCTAssertEqual(Recurrence("every 3 days"), Recurrence(interval: 3, unit: .day))
        XCTAssertEqual(Recurrence("every week"), Recurrence(unit: .week))
        XCTAssertEqual(Recurrence("every 2 weeks"), Recurrence(interval: 2, unit: .week))
        XCTAssertEqual(Recurrence("biweekly"), Recurrence(interval: 2, unit: .week))
        XCTAssertEqual(Recurrence("every other week"), Recurrence(interval: 2, unit: .week))
        XCTAssertEqual(Recurrence("every week on Monday, Thursday"), Recurrence(unit: .week, weekdays: [1, 4]))
        XCTAssertEqual(Recurrence("every Tuesday and Friday"), Recurrence(unit: .week, weekdays: [2, 5]))
        XCTAssertEqual(Recurrence("every weekday"), Recurrence(unit: .week, weekdays: [1, 2, 3, 4, 5]))
        XCTAssertEqual(Recurrence("every weekend"), Recurrence(unit: .week, weekdays: [6, 7]))
        XCTAssertEqual(Recurrence("every month when done"), Recurrence(unit: .month, whenDone: true))
        XCTAssertNil(Recurrence("every blue moon"))
        XCTAssertNil(Recurrence("sometimes"))
    }

    func testCanonicalText() {
        XCTAssertEqual(Recurrence("every week on thu, mon")?.text, "every week on Monday, Thursday")
        XCTAssertEqual(Recurrence("biweekly")?.text, "every 2 weeks")
        XCTAssertEqual(Recurrence("every weekday")?.text, "every weekday")
        XCTAssertEqual(Recurrence("every day when done")?.text, "every day when done")
    }

    func testNextDates() {
        XCTAssertEqual(Recurrence("every day")?.next(after: "2026-10-09", calendar: cal), "2026-10-10")
        XCTAssertEqual(Recurrence("every week")?.next(after: "2026-10-09", calendar: cal), "2026-10-16")
        XCTAssertEqual(Recurrence("every 2 weeks")?.next(after: "2026-10-09", calendar: cal), "2026-10-23")
        XCTAssertEqual(Recurrence("every weekday")?.next(after: "2026-10-09", calendar: cal), "2026-10-12") // Fri → Mon
        XCTAssertEqual(Recurrence("every weekend")?.next(after: "2026-10-09", calendar: cal), "2026-10-10")
        XCTAssertEqual(Recurrence("every weekend")?.next(after: "2026-10-11", calendar: cal), "2026-10-17") // Sun → Sat
        // Biweekly on Monday and Friday, from a Monday: Friday that week, then Monday two weeks on.
        let r = Recurrence("every 2 weeks on Monday, Friday")!
        XCTAssertEqual(r.next(after: "2026-10-05", calendar: cal), "2026-10-09")
        XCTAssertEqual(r.next(after: "2026-10-09", calendar: cal), "2026-10-19")
        XCTAssertEqual(Recurrence("every month")?.next(after: "2026-01-31", calendar: cal), "2026-02-28")
    }
}
