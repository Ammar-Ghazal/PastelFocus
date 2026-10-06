import XCTest
@testable import PastelFocusCore

final class LogCacheTests: XCTestCase {
    func event(_ id: String) -> TaskEvent {
        TaskEvent(at: ISO8601.date("2026-10-07T06:00:00Z")!, taskId: id, type: .created, actor: .you)
    }

    func testRepeatedReadsDoNotReparse() throws {
        let config = makeVault()
        let log = JSONLLog<TaskEvent>(directory: config.logsDir, prefix: "events", calendar: dubai)
        try log.append(event("a"), at: event("a").at)
        XCTAssertEqual(log.readAll().count, 1)
        let parsed = log.parseCount
        for _ in 0..<50 { _ = log.readAll() }
        XCTAssertEqual(log.parseCount, parsed, "unchanged files are served from cache")
    }

    func testAppendAndOutsideEditsInvalidate() throws {
        let config = makeVault()
        let log = JSONLLog<TaskEvent>(directory: config.logsDir, prefix: "events", calendar: dubai)
        try log.append(event("a"), at: event("a").at)
        XCTAssertEqual(log.readAll().map(\.taskId), ["a"])
        try log.append(event("b"), at: event("b").at)
        XCTAssertEqual(log.readAll().map(\.taskId), ["a", "b"], "an append is seen immediately")
        // Someone rewrites the file outside the app.
        let url = log.file(for: event("a").at)
        let text = read(url).replacingOccurrences(of: "\"a\"", with: "\"z\"")
        write(text, to: url)
        XCTAssertEqual(log.readAll().map(\.taskId), ["z", "b"])
    }

    func testCopiesShareTheCache() throws {
        let config = makeVault()
        let log = JSONLLog<TaskEvent>(directory: config.logsDir, prefix: "events", calendar: dubai)
        try log.append(event("a"), at: event("a").at)
        let copy = log
        _ = log.readAll()
        let parsed = copy.parseCount
        _ = copy.readAll()
        XCTAssertEqual(copy.parseCount, parsed)
    }
}
