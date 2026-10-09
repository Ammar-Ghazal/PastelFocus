import CoreGraphics
import XCTest
@testable import PastelFocusCore

final class PillReorderTests: XCTestCase {
    // Three pills of different widths on one row, and one wrapped onto a second row.
    let frames: [String: CGRect] = [
        "a": CGRect(x: 0, y: 0, width: 60, height: 34),
        "bb": CGRect(x: 68, y: 0, width: 100, height: 34),
        "c": CGRect(x: 176, y: 0, width: 50, height: 34),
        "d": CGRect(x: 0, y: 42, width: 70, height: 34),
    ]
    let order = ["a", "bb", "c", "d"]

    func testLeadingHalfGoesBeforeTrailingHalfAfter() {
        XCTAssertEqual(PillReorder.insertionIndex(of: "a", in: order, at: CGPoint(x: 80, y: 17), frames: frames), 0)
        XCTAssertEqual(PillReorder.insertionIndex(of: "a", in: order, at: CGPoint(x: 150, y: 17), frames: frames), 1)
        XCTAssertEqual(PillReorder.insertionIndex(of: "a", in: order, at: CGPoint(x: 20, y: 60), frames: frames), 2)
    }

    func testStableWhenPillsMoveAside() {
        // Dragging "a" to the trailing half of "bb" puts it after "bb". Asking again with the same
        // point gives the same answer, so applying it twice changes nothing.
        let point = CGPoint(x: 150, y: 17)
        let to = PillReorder.insertionIndex(of: "a", in: order, at: point, frames: frames)!
        let next = PillReorder.moving("a", to: to, in: order)
        XCTAssertEqual(next, ["bb", "a", "c", "d"])
        XCTAssertEqual(PillReorder.insertionIndex(of: "a", in: next, at: point, frames: frames), next.firstIndex(of: "a"))
    }

    func testOverNothingOrItselfKeepsOrder() {
        XCTAssertNil(PillReorder.insertionIndex(of: "a", in: order, at: CGPoint(x: 400, y: 17), frames: frames))
        XCTAssertNil(PillReorder.insertionIndex(of: "a", in: order, at: CGPoint(x: 30, y: 17), frames: frames))
    }

    func testGapBetweenRowsCountsAsRow() {
        XCTAssertEqual(PillReorder.insertionIndex(of: "d", in: order, at: CGPoint(x: 200, y: 38), frames: frames), 2)
    }

    func testMovingClampsIndex() {
        XCTAssertEqual(PillReorder.moving("a", to: 9, in: order), ["bb", "c", "d", "a"])
    }
}
