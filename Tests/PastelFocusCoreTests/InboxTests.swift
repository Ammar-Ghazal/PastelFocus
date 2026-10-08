import XCTest
@testable import PastelFocusCore

final class InboxTests: XCTestCase {
    final class FakeActions: FocusActions {
        var suggested: [(String, Int, String?)] = []
        var allowStart = false
        var started: [String] = []
        func suggestFocus(task: TaskItem, minutes: Int, why: String?) -> Bool { suggested.append((task.taskID!, minutes, why)); return true }
        func startFocus(task: TaskItem, minutes: Int) -> String? {
            guard allowStart else { return "Hermes isn't allowed to start sessions (Settings)" }
            started.append(task.taskID!); return nil
        }
    }

    var config: VaultConfig!
    var store: TaskStore!
    var inbox: InboxProcessor!
    var actions: FakeActions!

    override func setUp() {
        config = makeVault()
        let clock = FixedClock("2026-10-07T06:02:00Z")
        store = TaskStore(config: config, calendar: dubai, clock: clock)
        inbox = InboxProcessor(store: store, calendar: dubai, clock: clock)
        actions = FakeActions()
        inbox.actions = actions
        write("## Today's task list\n\n- [ ] Finalize resume #career 🆔 r7q2\n- [ ] Exercise cron #health 🆔 e1w5\n", to: config.dailyNote("2026-10-07"))
    }

    func addCommands(_ lines: [String]) {
        write((InboxProcessor.header + lines.map { "- [ ] " + $0 }).joined(separator: "\n") + "\n", to: config.inbox)
    }

    func testParseCommands() throws {
        XCTAssertEqual(try InboxProcessor.parse("reschedule 🆔 r7q2 ⏳ 2026-10-09 — reason: waiting on references"),
                       .init(command: .reschedule(id: "r7q2", day: "2026-10-09"), actor: .hermes, reason: "waiting on references"))
        XCTAssertEqual(try InboxProcessor.parse("priority 🆔 c4x8 ⏫").command, .priority(id: "c4x8", .high))
        XCTAssertEqual(try InboxProcessor.parse("priority 🆔 c4x8 🔺").command, .priority(id: "c4x8", .urgent))
        XCTAssertEqual(try InboxProcessor.parse("priority 🆔 c4x8 urgent").command, .priority(id: "c4x8", .urgent))
        XCTAssertEqual(try InboxProcessor.parse("estimate 🆔 c4x8 3").command, .estimate(id: "c4x8", sessions: 3))
        XCTAssertEqual(try InboxProcessor.parse("suggest-focus 🆔 r7q2 40m — why: best slot").command, .suggestFocus(id: "r7q2", minutes: 40))
        XCTAssertEqual(try InboxProcessor.parse("complete 🆔 e1w5 #by-you").actor, .you)
        XCTAssertThrowsError(try InboxProcessor.parse("fly 🆔 r7q2"))
        XCTAssertThrowsError(try InboxProcessor.parse("complete"))
    }

    func testProcessAppliesAndTicksEachLine() throws {
        addCommands([
            "complete 🆔 e1w5",
            "create Mock interview prep #learning ⏫ [est:: 2]",
            "reschedule 🆔 r7q2 ⏳ 2026-10-09 — reason: blocked",
            "complete 🆔 nope",
        ])
        XCTAssertEqual(try inbox.process(), 4)
        let text = read(config.inbox)
        XCTAssertTrue(text.contains("- [x] complete 🆔 e1w5 → applied 10:02 by hermes"))
        XCTAssertTrue(text.contains("- [x] create Mock interview prep #learning ⏫ [est:: 2] → created 🆔 "))
        XCTAssertTrue(text.contains("- [x] complete 🆔 nope → error: Couldn't find task 🆔 nope."))
        XCTAssertEqual(store.find("e1w5")?.status, .done)
        XCTAssertEqual(store.find("r7q2")?.scheduled, "2026-10-09")
        let events = store.events.readAll()
        XCTAssertTrue(events.allSatisfy { $0.actor == .hermes })
        XCTAssertEqual(events.first { $0.type == .rescheduled }?.reason, "blocked")
        // Already-processed lines are not applied twice.
        XCTAssertEqual(try inbox.process(), 0)
    }

    func testFocusCommandsGoThroughTheApp() throws {
        addCommands(["suggest-focus 🆔 r7q2 40m — why: writing goes best before noon", "start-focus 🆔 r7q2 25m"])
        try inbox.process()
        XCTAssertEqual(actions.suggested.first?.1, 40)
        XCTAssertEqual(actions.suggested.first?.2, "writing goes best before noon")
        XCTAssertTrue(read(config.inbox).contains("start-focus 🆔 r7q2 25m → error: Hermes isn't allowed to start sessions (Settings)"))
        XCTAssertTrue(actions.started.isEmpty)
    }

    func testCreatesInboxWithHeaderWhenMissing() throws {
        XCTAssertEqual(try inbox.process(), 0)
        XCTAssertTrue(read(config.inbox).hasPrefix("# PastelFocus Inbox"))
    }
}
