import Foundation

/// Reads and writes task lines in the Obsidian Tasks plugin format, plus the legacy
/// `**P1 · 90 min** Title — detail` lines that Hermes wrote before PastelFocus.
public enum TaskLineParser {
    static let checkbox = try! NSRegularExpression(pattern: #"^(\s*)[-*] \[(.)\] (.*)$"#)
    static let idField = try! NSRegularExpression(pattern: #"\s*🆔\s*([A-Za-z0-9_-]+)"#)
    static let dateField = try! NSRegularExpression(pattern: #"\s*(➕|⏳|📅|🛫|✅|❌)\s*(\d{4}-\d{2}-\d{2})"#)
    static let priorityField = try! NSRegularExpression(pattern: #"\s*(🔺|⏫|🔼|🔽|⏬)️?"#)
    /// The rule runs to the next field or tag, as the Tasks plugin reads it: `🔁 every week on Monday`.
    static let recurrenceField = try! NSRegularExpression(pattern: #"\s*🔁\s*([A-Za-z0-9,! ]*[A-Za-z0-9!])"#)
    static let inlineField = try! NSRegularExpression(pattern: #"\s*\[(est|sessions|spent|progress)::\s*([^\]]*?)\s*\]"#)
    static let legacyMarker = try! NSRegularExpression(pattern: #"\*\*P([123])\s*·\s*([0-9.]+)(?:\s*[–-]\s*([0-9.]+))?\s*(min|h)\*\*\s*"#)
    static let tagPattern = try! NSRegularExpression(pattern: #"(?<![\w#])#([A-Za-z][\w/-]*)"#)

    /// Minutes in one classic focus session; used to turn an old `[sessions:: N]` count into time
    /// when the sessions log has nothing for the task.
    public static let minutesPerSession = 25

    public static func isTaskLine(_ line: String) -> Bool {
        checkbox.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    /// Parses one line. Returns nil when the line is not a checkbox item.
    public static func parse(_ line: String, file: String = "", lineIndex: Int = 0) -> TaskItem? {
        let ns = line as NSString
        guard let m = checkbox.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let indent = ns.substring(with: m.range(at: 1))
        let marker = Character(ns.substring(with: m.range(at: 2)))
        var text = ns.substring(with: m.range(at: 3))

        var item = TaskItem(status: TaskStatus(marker: marker), description: "", file: file, lineIndex: lineIndex, indent: indent)

        if let id = extract(idField, from: &text).first { item.taskID = id[1] }
        for match in extract(dateField, from: &text) {
            switch match[1] {
            case "➕": item.created = match[2]
            case "⏳": item.scheduled = match[2]
            case "📅": item.due = match[2]
            case "🛫": item.start = match[2]
            case "✅": item.completed = match[2]
            case "❌": if item.status == .todo { item.status = .cancelled }
            default: break
            }
        }
        for match in extract(priorityField, from: &text) {
            switch match[1] {
            case "🔺": item.priority = .urgent
            case "⏫": item.priority = .high
            case "🔼": item.priority = .medium
            case "🔽", "⏬": item.priority = .low
            default: break
            }
        }
        if let r = extract(recurrenceField, from: &text).first { item.recurrence = r[1] }
        for match in extract(inlineField, from: &text) {
            switch match[1] {
            case "est": item.legacyEstimate = Int(match[2])
            case "sessions": item.legacySessions = Int(match[2])
            case "progress": item.progress = Int(match[2].replacingOccurrences(of: "%", with: "")).map { min(100, max(0, $0)) }
            default: item.spentMinutes = parseMinutes(match[2])
            }
        }

        let tns = text as NSString
        if let lm = legacyMarker.firstMatch(in: text, range: NSRange(location: 0, length: tns.length)) {
            if item.priority == .none {
                switch tns.substring(with: lm.range(at: 1)) {
                case "1": item.priority = .high
                case "2": item.priority = .medium
                default: item.priority = .low
                }
                item.priorityFromLegacy = true
            }
        }

        item.description = collapseSpaces(text)
        return item
    }

    /// Canonical line: description, inline fields, then Tasks plugin emoji fields (which must come last).
    public static func serialize(_ t: TaskItem) -> String {
        var parts: [String] = [t.description]
        // An old session count that hasn't been migrated yet is kept as time rather than dropped.
        let spent = t.spentMinutes ?? t.legacySessions.map { $0 * minutesPerSession }
        if let m = spent, m > 0 { parts.append("[spent:: \(formatMinutes(m))]") }
        if let p = t.progress { parts.append("[progress:: \(p)]") }
        if !t.priorityFromLegacy, let p = t.priority.emoji { parts.append(p) }
        if let r = t.recurrence { parts.append("🔁 \(r)") }
        if let d = t.created { parts.append("➕ \(d)") }
        if let d = t.start { parts.append("🛫 \(d)") }
        if let d = t.scheduled { parts.append("⏳ \(d)") }
        if let d = t.due { parts.append("📅 \(d)") }
        if let d = t.completed { parts.append("✅ \(d)") }
        if let id = t.taskID { parts.append("🆔 \(id)") }
        let body = parts.filter { !$0.isEmpty }.joined(separator: " ")
        return "\(t.indent)- [\(t.status.rawValue)] \(body)"
    }

    // MARK: Helpers

    /// "25m", "2h", "1h 25m": the `[spent::]` value.
    public static func formatMinutes(_ m: Int) -> String {
        m < 60 ? "\(m)m" : m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
    }

    /// Reads "1h 25m", "1h25m", "2h", "85m", "85 min" or a bare number of minutes.
    public static func parseMinutes(_ s: String) -> Int? {
        let t = s.lowercased().replacingOccurrences(of: " ", with: "")
        if let n = Int(t) { return n }
        guard let re = try? NSRegularExpression(pattern: #"^(?:(\d+)h)?(?:(\d+)m(?:in)?)?$"#),
              let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)), !t.isEmpty else { return nil }
        let ns = t as NSString
        func group(_ i: Int) -> Int { m.range(at: i).location == NSNotFound ? 0 : Int(ns.substring(with: m.range(at: i))) ?? 0 }
        return group(1) * 60 + group(2)
    }

    public static func tags(in text: String) -> [String] {
        let ns = text as NSString
        return tagPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }

    public static func removingTags(_ text: String) -> String {
        let ns = text as NSString
        let stripped = tagPattern.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        return collapseSpaces(stripped)
    }

    public static func stripLegacyMarker(_ text: String) -> String {
        let ns = text as NSString
        return legacyMarker.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "")
    }

    static func collapseSpaces(_ s: String) -> String {
        s.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    /// Removes every match of `regex` from `text` and returns the capture groups of each match.
    static func extract(_ regex: NSRegularExpression, from text: inout String) -> [[String]] {
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        let groups = matches.map { m in (0..<m.numberOfRanges).map { i -> String in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        } }
        let mutable = NSMutableString(string: text)
        for m in matches.reversed() { mutable.replaceCharacters(in: m.range, with: " ") }
        text = mutable as String
        return groups
    }

    /// A short random task ID such as `r7q2`.
    public static func newID<G: RandomNumberGenerator>(using rng: inout G) -> String {
        let alphabet = Array("abcdefghijkmnpqrstuvwxyz23456789")
        return String((0..<4).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &rng)] })
    }

    public static func newID() -> String {
        var g = SystemRandomNumberGenerator()
        return newID(using: &g)
    }
}
