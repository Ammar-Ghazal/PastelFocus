import XCTest
@testable import PastelFocusCore

final class TaskSortTests: XCTestCase {
    private func task(_ line: String) -> TaskItem { TaskLineParser.parse(line)! }

    func testFourPrioritiesRoundTrip() throws {
        for (emoji, p) in [("🔺", Priority.urgent), ("⏫", .high), ("🔼", .medium), ("🔽", .low)] {
            let line = "- [ ] Thing #coding \(emoji) 🆔 ab12"
            let t = task(line)
            XCTAssertEqual(t.priority, p)
            XCTAssertEqual(TaskLineParser.serialize(t), line)
        }
        XCTAssertEqual(task("- [ ] Thing ⏬").priority, .low, "lowest is read as low")
    }

    func testPriorityOrder() {
        let tasks = [
            task("- [ ] Low 🔽"), task("- [ ] Plain"), task("- [x] Done urgent 🔺"), task("- [ ] Later urgent #later 🔺"),
            task("- [ ] Medium 🔼"), task("- [ ] Urgent 🔺"), task("- [ ] High ⏫"), task("- [ ] Plain two"),
        ]
        XCTAssertEqual(TaskSort.priority.sorted(tasks).map(\.title),
                       ["Urgent", "High", "Medium", "Plain", "Plain two", "Low", "Later urgent", "Done urgent"])
    }

    func testTitleOrder() {
        let tasks = [task("- [ ] banana ⏫"), task("- [ ] Apple 2"), task("- [ ] Apple 10 🔺"), task("- [x] aardvark")]
        XCTAssertEqual(TaskSort.title.sorted(tasks).map(\.title), ["Apple 2", "Apple 10", "banana", "aardvark"],
                       "natural order, case-insensitive; finished tasks still last")
    }

    func testTagOrderUsesFirstTagThenPriority() {
        let tasks = [task("- [ ] No tag 🔺"), task("- [ ] Code low #coding 🔽"), task("- [ ] Admin #admin #coding"),
                     task("- [ ] Code urgent #coding 🔺"), task("- [ ] Deferred #later #admin")]
        XCTAssertEqual(TaskSort.tag.sorted(tasks).map(\.title), ["Admin", "Code urgent", "Code low", "No tag", "Deferred"])
    }
}
