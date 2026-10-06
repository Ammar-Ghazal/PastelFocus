import Foundation

/// Append-only monthly JSON Lines files, e.g. `sessions-2026-10.jsonl`. Written only by the app.
public struct JSONLLog<Record: Codable>: Sendable {
    public let directory: URL
    public let prefix: String
    public let calendar: DayCalendar

    public init(directory: URL, prefix: String, calendar: DayCalendar) {
        self.directory = directory
        self.prefix = prefix
        self.calendar = calendar
    }

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public func file(for date: Date) -> URL {
        directory.appendingPathComponent("\(prefix)-\(calendar.month(date)).jsonl")
    }

    public func append(_ record: Record, at date: Date) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(record) + Data("\n".utf8)
        let url = file(for: date)
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            try h.seekToEnd()
            try h.write(contentsOf: data)
        } else {
            try data.write(to: url)
        }
    }

    /// Every record in every month file, oldest file first. Malformed lines are skipped.
    public func readAll() -> [Record] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return [] }
        let files = names.filter { $0.hasPrefix(prefix + "-") && $0.hasSuffix(".jsonl") }.sorted()
        var out: [Record] = []
        for name in files {
            guard let text = try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") where !line.isEmpty {
                if let r = try? Self.decoder.decode(Record.self, from: Data(line.utf8)) { out.append(r) }
            }
        }
        return out
    }
}
