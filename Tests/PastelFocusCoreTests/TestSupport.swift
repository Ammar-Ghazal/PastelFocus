import Foundation
@testable import PastelFocusCore

final class FixedClock: Clock, @unchecked Sendable {
    var date: Date
    init(_ iso: String) { date = ISO8601.date(iso)! }
    func now() -> Date { date }
    func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
    func set(_ iso: String) { date = ISO8601.date(iso)! }
}

let dubai = DayCalendar(timeZone: TimeZone(identifier: "Asia/Dubai")!)

/// A throwaway vault in the temp directory.
func makeVault(logsInVault: Bool = true) -> VaultConfig {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("pf-vault-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let priv = root.appendingPathComponent(".private-logs")
    return VaultConfig(root: root, logsInVault: logsInVault, privateLogs: priv)
}

func write(_ text: String, to url: URL) {
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! text.write(to: url, atomically: true, encoding: .utf8)
}

func read(_ url: URL) -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }
