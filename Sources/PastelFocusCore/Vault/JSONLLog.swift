import Foundation

/// Append-only monthly JSON Lines files, e.g. `sessions-2026-10.jsonl`. Written only by the app.
/// Reads are cached per file and re-parsed only when that file's size or modification date changes,
/// so the many small reads behind each UI update cost a `stat`, not a parse.
public struct JSONLLog<Record: Codable>: @unchecked Sendable {
    public let directory: URL
    public let prefix: String
    public let calendar: DayCalendar
    private let cache = Cache()

    final class Cache: @unchecked Sendable {
        struct Entry { let size: Int; let mtime: Date?; let records: [Record] }
        private var entries: [String: Entry] = [:]
        private let lock = NSLock()
        /// Number of files parsed (not served from cache); for tests.
        private(set) var parses = 0

        func records(for url: URL, parse: () -> [Record]) -> [Record] {
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attrs?[.size] as? Int) ?? -1, mtime = attrs?[.modificationDate] as? Date
            lock.lock(); defer { lock.unlock() }
            if let e = entries[url.path], e.size == size, e.mtime == mtime { return e.records }
            let r = parse()
            parses += 1
            entries[url.path] = Entry(size: size, mtime: mtime, records: r)
            return r
        }
    }

    public init(directory: URL, prefix: String, calendar: DayCalendar) {
        self.directory = directory
        self.prefix = prefix
        self.calendar = calendar
    }

    /// Files parsed since this log was created (cache misses). Used by tests.
    public var parseCount: Int { cache.parses }

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
            let url = directory.appendingPathComponent(name)
            out += cache.records(for: url) {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
                let d = Self.decoder
                return text.split(separator: "\n").compactMap { line in
                    line.isEmpty ? nil : try? d.decode(Record.self, from: Data(line.utf8))
                }
            }
        }
        return out
    }
}
