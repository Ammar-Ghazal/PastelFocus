import Foundation

/// Stop-early reasons: three built-ins plus up to `maxSaved` custom ones the user chose to keep.
public enum StopReasons {
    public static let builtIn = ["interrupted", "blocked", "done early"]
    public static let maxSaved = 6
    /// Longest label shown on a chip or in the daily note's focus log.
    public static let maxLength = 22

    /// Tidies what was typed: trims, collapses spaces, lowercases the first letter, drops trailing
    /// punctuation and cuts at a word boundary with "…" if it's longer than `maxLength`.
    public static func shorten(_ raw: String, limit: Int = maxLength) -> String {
        var s = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        while let last = s.last, ".,;:!".contains(last) { s.removeLast() }
        if let first = s.first, s.count > 1, !(s.dropFirst().first?.isUppercase ?? false) {
            s = first.lowercased() + s.dropFirst()
        }
        guard s.count > limit else { return s }
        let cut = String(s.prefix(limit - 1))
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) >= limit / 2 {
            return String(cut[..<space]) + "…"
        }
        return cut + "…"
    }

    /// Adds a custom reason to the saved list (shortened, de-duplicated, newest first, capped).
    public static func saving(_ raw: String, to saved: [String]) -> [String] {
        let label = shorten(raw)
        guard !label.isEmpty, !builtIn.contains(label.lowercased()) else { return saved }
        let rest = saved.filter { $0.lowercased() != label.lowercased() }
        return Array(([label] + rest).prefix(maxSaved))
    }
}
