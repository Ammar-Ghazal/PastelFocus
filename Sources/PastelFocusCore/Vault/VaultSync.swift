import Foundation

// Real-time sync with the vault. The app's file watcher hears about every change under the daily
// folder and the PastelFocus folder; this decides which ones matter and whether anything changed
// since the app last read or wrote the task files. That keeps unrelated edits (wiki pages, the
// app's own logs and reports) and echoes of the app's own writes from causing a rescan, so the
// app and Hermes can't wake each other in a loop.

extension VaultConfig {
    /// A path whose change can affect tasks: an immediate `.md` file in the daily folder, or
    /// Backlog.md, Inbox.md or Tags.md. Hidden files (Obsidian's and the app's temp files) and
    /// everything else don't count.
    public func isTaskSource(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard !url.lastPathComponent.hasPrefix("."), url.pathExtension == "md" else { return false }
        if [backlog, inbox, tags].contains(where: { $0.standardizedFileURL.path == url.path }) { return true }
        return url.deletingLastPathComponent().path == dailyDir.standardizedFileURL.path
    }
}

/// Size and modification time of every file tasks are read from, keyed by path.
public struct VaultSnapshot: Equatable, Sendable {
    public var files: [String: SafeFile.Signature] = [:]

    /// What differs from `old` (files that appeared, changed or went away), or nil when nothing does.
    public func changes(since old: VaultSnapshot) -> VaultChange? {
        let changed = Set(files.keys).union(old.files.keys).filter { files[$0] != old.files[$0] }
        guard !changed.isEmpty else { return nil }
        return VaultChange(paths: changed, newest: changed.compactMap { files[$0]?.mtime }.max())
    }
}

public struct VaultChange: Equatable, Sendable {
    public var paths: Set<String>
    /// The newest modification time among them; nil if they were all deleted.
    public var newest: Date?
}

extension TaskStore {
    /// Every file that can hold tasks or task commands.
    public func watchedFiles() -> [URL] { taskFiles() + [config.inbox, config.tags] }

    public func snapshot() -> VaultSnapshot {
        VaultSnapshot(files: Dictionary(watchedFiles().map { ($0.standardizedFileURL.path, SafeFile.signature($0)) },
                                        uniquingKeysWith: { a, _ in a }))
    }
}

/// How long vault changes take to show in the app: from the file's modification time to the
/// panels being updated. Keeps the last `capacity` samples.
public struct SyncLatency: Sendable {
    public private(set) var samples: [TimeInterval] = []
    public let capacity: Int
    /// Changes should show within this, 95% of the time.
    public static let target: TimeInterval = 1.0

    public init(capacity: Int = 50) { self.capacity = capacity }

    public mutating func record(_ seconds: TimeInterval) {
        samples.append(max(0, seconds))
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
    }

    public var last: TimeInterval? { samples.last }
    public var p50: TimeInterval? { percentile(0.5) }
    public var p95: TimeInterval? { percentile(0.95) }

    func percentile(_ p: Double) -> TimeInterval? {
        guard !samples.isEmpty else { return nil }
        let s = samples.sorted()
        return s[min(s.count - 1, Int((Double(s.count - 1) * p).rounded(.up)))]
    }
}
