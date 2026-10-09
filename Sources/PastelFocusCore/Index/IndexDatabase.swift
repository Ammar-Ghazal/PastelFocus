import Foundation
import SQLite3

/// Private SQLite cache built from the vault files. Safe to delete: `rebuild` recreates it.
public final class IndexDatabase {
    public let url: URL
    private var db: OpaquePointer?

    public enum IndexError: Error { case open(String), exec(String) }

    public init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw IndexError.open(url.path) }
        try exec("PRAGMA journal_mode=WAL;")
        // Version 2: tasks.est and tasks.actual (session counts) became tasks.spent_min. The index is
        // a cache, so an older tasks table is dropped and refilled by the next rebuild.
        if userVersion() < Self.schemaVersion {
            try exec("DROP TABLE IF EXISTS tasks; PRAGMA user_version = \(Self.schemaVersion);")
        }
        try exec("""
        CREATE TABLE IF NOT EXISTS tasks(id TEXT PRIMARY KEY, title TEXT, status TEXT, category TEXT, priority INTEGER,
            spent_min INTEGER, created TEXT, scheduled TEXT, due TEXT, completed TEXT, file TEXT);
        CREATE TABLE IF NOT EXISTS sessions(id TEXT PRIMARY KEY, kind TEXT, task_id TEXT, category TEXT, planned_s INTEGER,
            started_at REAL, ended_at REAL, focused_s INTEGER, outcome TEXT, pause_count INTEGER, pause_s INTEGER);
        CREATE TABLE IF NOT EXISTS events(at REAL, task_id TEXT, type TEXT, field TEXT, old TEXT, new TEXT, actor TEXT, reason TEXT);
        CREATE TABLE IF NOT EXISTS insights(kind TEXT, scope TEXT, title TEXT, evidence TEXT, value REAL, baseline REAL,
            sample_n INTEGER, computed_at REAL);
        CREATE INDEX IF NOT EXISTS sessions_task ON sessions(task_id);
        CREATE INDEX IF NOT EXISTS sessions_start ON sessions(started_at);
        """)
    }

    deinit { sqlite3_close(db) }

    static let schemaVersion: Int32 = 2

    private func userVersion() -> Int32 {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK, sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return sqlite3_column_int(stmt, 0)
    }

    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw IndexError.exec(msg)
        }
    }

    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func insert(_ sql: String, rows: [[Any?]]) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw IndexError.exec(sql) }
        defer { sqlite3_finalize(stmt) }
        for row in rows {
            sqlite3_reset(stmt)
            for (i, v) in row.enumerated() {
                let idx = Int32(i + 1)
                switch v {
                case let s as String: sqlite3_bind_text(stmt, idx, s, -1, transient)
                case let n as Int: sqlite3_bind_int64(stmt, idx, Int64(n))
                case let d as Double: sqlite3_bind_double(stmt, idx, d)
                default: sqlite3_bind_null(stmt, idx)
                }
            }
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw IndexError.exec(String(cString: sqlite3_errmsg(db))) }
        }
    }

    /// Replaces the whole index with what the vault says now.
    public func rebuild(tasks: [TaskItem], sessions: [SessionRecord], events: [TaskEvent], insights: [Insight]) throws {
        try exec("BEGIN; DELETE FROM tasks; DELETE FROM sessions; DELETE FROM events; DELETE FROM insights;")
        do {
            try insert("INSERT OR REPLACE INTO tasks VALUES(?,?,?,?,?,?,?,?,?,?,?)", rows: tasks.compactMap { t in
                guard let id = t.taskID else { return nil }
                return [id, t.title, t.status.rawValue, t.category, t.priority.rawValue, t.spentMinutes,
                        t.created, t.scheduled, t.due, t.completed, t.file]
            })
            try insert("INSERT OR REPLACE INTO sessions VALUES(?,?,?,?,?,?,?,?,?,?,?)", rows: sessions.map { s in
                [s.id, s.kind.rawValue, s.taskId, s.category, s.plannedS, s.startedAt.timeIntervalSince1970,
                 s.endedAt.timeIntervalSince1970, s.focusedS, s.outcome.rawValue, s.pauses.count, s.pauses.reduce(0) { $0 + $1.durS }]
            })
            try insert("INSERT INTO events VALUES(?,?,?,?,?,?,?,?)", rows: events.map { e in
                [e.at.timeIntervalSince1970, e.taskId, e.type.rawValue, e.field, e.old, e.new, e.actor.rawValue, e.reason]
            })
            try insert("INSERT INTO insights VALUES(?,?,?,?,?,?,?,?)", rows: insights.map { i in
                [i.kind, i.scope, i.title, i.evidence, i.value, i.baseline, i.sampleN, i.computedAt.timeIntervalSince1970]
            })
            try exec("COMMIT;")
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    public func scalarInt(_ sql: String, _ args: [String] = []) -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        for (i, a) in args.enumerated() { sqlite3_bind_text(stmt, Int32(i + 1), a, -1, transient) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int64(stmt, 0)) : 0
    }

    /// Completed focus sessions linked to a task.
    public func completedSessions(forTask id: String) -> Int {
        scalarInt("SELECT COUNT(*) FROM sessions WHERE task_id = ? AND kind = 'focus' AND outcome = 'completed'", [id])
    }

    /// Focused seconds between two instants.
    public func focusedSeconds(from: Date, to: Date) -> Int {
        scalarInt("SELECT COALESCE(SUM(focused_s),0) FROM sessions WHERE kind='focus' AND started_at >= \(from.timeIntervalSince1970) AND started_at < \(to.timeIntervalSince1970)")
    }

    public func count(_ table: String) -> Int { scalarInt("SELECT COUNT(*) FROM \(table)") }
}
