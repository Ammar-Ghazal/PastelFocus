import XCTest
@testable import PastelFocusCore

final class DialMathTests: XCTestCase {
    func testAngleToMinutes() {
        // One full turn = 120 min; 12 o'clock is the start, clockwise.
        XCTAssertEqual(DialMath.minutes(dx: 1, dy: 0), 30)      // 3 o'clock
        XCTAssertEqual(DialMath.minutes(dx: 0, dy: 1), 60)      // 6 o'clock
        XCTAssertEqual(DialMath.minutes(dx: -1, dy: 0), 90)     // 9 o'clock
        XCTAssertEqual(DialMath.minutes(dx: 0.0001, dy: -1), 5, "just past 12 clamps to the 5-min minimum")
        XCTAssertEqual(DialMath.minutes(dx: -0.0001, dy: -1), 120, "just before 12 is the maximum")
    }

    func testSnapsToFiveMinuteSteps() {
        let a = 47.0 / 120 * 2 * Double.pi // 47 minutes' worth of angle
        XCTAssertEqual(DialMath.minutes(dx: sin(a), dy: -cos(a)), 45)
    }

    func testNudgeAndClamp() {
        XCTAssertEqual(DialMath.nudge(25, by: 1), 30)
        XCTAssertEqual(DialMath.nudge(5, by: -1), 5)
        XCTAssertEqual(DialMath.nudge(120, by: 1), 120)
        XCTAssertEqual(DialMath.nudge(27, by: 1), 30, "off-grid values snap onto the grid")
        XCTAssertEqual(DialMath.fraction(60), 0.5)
    }

    func testDragDoesNotWrapAcrossTwelve() {
        XCTAssertEqual(DialMath.continuing(from: 115, to: 5), 120)
        XCTAssertEqual(DialMath.continuing(from: 10, to: 120), 5)
        XCTAssertEqual(DialMath.continuing(from: 25, to: 30), 30)
    }

    func testRestScalesWithFocusLength() {
        XCTAssertEqual(FocusPreset.forFocus(25), FocusPreset(focusMinutes: 25, shortRestMinutes: 5, longRestMinutes: 15))
        XCTAssertEqual(FocusPreset.forFocus(50), FocusPreset(focusMinutes: 50, shortRestMinutes: 10, longRestMinutes: 30))
        XCTAssertEqual(FocusPreset.forFocus(10).shortRestMinutes, 3, "rest never drops below 3 min")
        XCTAssertEqual(FocusPreset.forFocus(120).shortRestMinutes, 20, "rest caps at 20 min")
    }
}
