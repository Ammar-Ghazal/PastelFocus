import Foundation

public enum SafeFileError: Error, Equatable, CustomStringConvertible {
    case conflict(String)
    case lineNotFound(String)

    public var description: String {
        switch self {
        case .conflict(let p): return "Couldn't save \(p): it changed while saving. Try again."
        case .lineNotFound(let what): return "Couldn't find \(what)."
        }
    }
}

/// Line-level file edits that never clobber a concurrent writer (Hermes, Obsidian, you):
/// re-read before writing, write a temp file, rename it into place, retry once on conflict.
public enum SafeFile {
    public static func readLines(_ url: URL) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    /// Applies `transform` to the file's lines and saves atomically. Creates the file (and folders) if missing.
    public static func edit(_ url: URL, retries: Int = 1, _ transform: (inout [String]) throws -> Void) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        for attempt in 0...retries {
            let before = signature(url)
            var lines = readLines(url)
            try transform(&lines)
            let text = lines.joined(separator: "\n") + "\n"
            let tmp = url.deletingLastPathComponent()
                .appendingPathComponent(".\(url.lastPathComponent).pf-\(UUID().uuidString.prefix(8)).tmp")
            try text.write(to: tmp, atomically: false, encoding: .utf8)
            if signature(url) != before {
                try? fm.removeItem(at: tmp)
                if attempt == retries { throw SafeFileError.conflict(url.lastPathComponent) }
                continue
            }
            if rename(tmp.path, url.path) != 0 {
                try? fm.removeItem(at: tmp)
                throw CocoaError(.fileWriteUnknown)
            }
            return
        }
    }

    /// Appends one line, creating the file with `header` lines if it does not exist.
    public static func appendLine(_ line: String, to url: URL, header: [String] = []) throws {
        try edit(url) { lines in
            if lines.isEmpty { lines = header }
            lines.append(line)
        }
    }

    /// Appends `line` at the end of the `## heading` section (creating the section at the end of the file).
    public static func appendToSection(_ heading: String, line: String, in url: URL, fileHeader: [String] = []) throws {
        try edit(url) { lines in
            if lines.isEmpty { lines = fileHeader }
            if let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == heading }) {
                var end = start + 1
                while end < lines.count, !lines[end].hasPrefix("## ") { end += 1 }
                // Insert after the last non-blank line of the section.
                var insertAt = end
                while insertAt > start + 1, lines[insertAt - 1].trimmingCharacters(in: .whitespaces).isEmpty { insertAt -= 1 }
                lines.insert(line, at: insertAt)
            } else {
                if let last = lines.last, !last.isEmpty { lines.append("") }
                lines.append(heading)
                lines.append("")
                lines.append(line)
            }
        }
    }

    struct Signature: Equatable { let size: Int; let mtime: Date? ; let exists: Bool }

    static func signature(_ url: URL) -> Signature {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return Signature(size: -1, mtime: nil, exists: false)
        }
        return Signature(size: (a[.size] as? Int) ?? -1, mtime: a[.modificationDate] as? Date, exists: true)
    }
}
