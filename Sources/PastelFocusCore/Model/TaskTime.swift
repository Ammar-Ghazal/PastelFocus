import Foundation

/// The time of day at the start of a task line: `07:00 Title` or `07:00 - 07:45 Title`, the way
/// Hermes already writes timed tasks and the Obsidian Day Planner plugin reads them. 24-hour clock.
public enum TaskTime {
    static let pattern = try! NSRegularExpression(pattern: #"^(\d{1,2}):(\d{2})(?:\s*(?:-|–|to)\s*(\d{1,2}):(\d{2}))?(?:\s+|$)"#)

    /// The start ("HH:MM"), the length of a range in minutes, and the text after them.
    static func leading(_ text: String) -> (String, Int?, String)? {
        let ns = text as NSString
        guard let m = pattern.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              let h = Int(ns.substring(with: m.range(at: 1))), let mi = Int(ns.substring(with: m.range(at: 2))),
              h < 24, mi < 60 else { return nil }
        let start = h * 60 + mi
        var length: Int?
        if m.range(at: 3).location != NSNotFound,
           let h2 = Int(ns.substring(with: m.range(at: 3))), let m2 = Int(ns.substring(with: m.range(at: 4))), h2 < 24, m2 < 60 {
            let end = h2 * 60 + m2
            length = end > start ? end - start : end + 24 * 60 - start // a range past midnight
        }
        let rest = ns.substring(from: m.range.location + m.range.length).trimmingCharacters(in: .whitespaces)
        return (string(start), length, rest)
    }

    /// What `serialize` puts in front of the description.
    static func prefix(_ t: TaskItem) -> String {
        guard let s = t.startTime else { return "" }
        if let e = t.endTime { return "\(s) - \(e) " }
        return "\(s) "
    }

    /// "07:45" → 465.
    public static func minutes(_ hhmm: String) -> Int? {
        let p = hhmm.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2, (0..<24).contains(p[0]), (0..<60).contains(p[1]) else { return nil }
        return p[0] * 60 + p[1]
    }

    /// 465 → "07:45".
    public static func string(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }
}
