import Foundation

/// A repeat rule from a task's `🔁` field, in the Obsidian Tasks plugin's words:
/// `every day`, `every 3 days`, `every week`, `every 2 weeks` (biweekly), `every week on Monday, Thursday`,
/// `every weekday` (Monday–Friday), `every weekend` (Saturday and Sunday), `every Tuesday`,
/// `every month`, `every 2 months`, each optionally followed by `when done`.
/// Rules it can't read stay on the line as text; the task still counts as repeating.
public struct Recurrence: Equatable, Sendable {
    public enum Unit: String, Sendable { case day, week, month }

    public var interval: Int
    public var unit: Unit
    /// ISO weekdays (1 = Monday … 7 = Sunday) for weekly rules; empty means "the same weekday".
    public var weekdays: Set<Int>
    /// The next date counts from the day it's done rather than the day it was planned.
    public var whenDone: Bool

    public init(interval: Int = 1, unit: Unit, weekdays: Set<Int> = [], whenDone: Bool = false) {
        self.interval = max(1, interval)
        self.unit = unit
        self.weekdays = weekdays
        self.whenDone = whenDone
    }

    static let dayNames = ["monday": 1, "tuesday": 2, "wednesday": 3, "thursday": 4, "friday": 5, "saturday": 6, "sunday": 7]
    static let weekdaySet: Set<Int> = [1, 2, 3, 4, 5]
    static let weekendSet: Set<Int> = [6, 7]

    public init?(_ raw: String) {
        var s = raw.lowercased().trimmingCharacters(in: .whitespaces)
        var whenDone = false
        if s.hasSuffix("when done") { whenDone = true; s = String(s.dropLast(9)).trimmingCharacters(in: .whitespaces) }
        switch s {
        case "daily": self.init(unit: .day, whenDone: whenDone); return
        case "weekly": self.init(unit: .week, whenDone: whenDone); return
        case "biweekly", "fortnightly": self.init(interval: 2, unit: .week, whenDone: whenDone); return
        case "monthly": self.init(unit: .month, whenDone: whenDone); return
        default: break
        }
        guard s.hasPrefix("every ") else { return nil }
        s = String(s.dropFirst(6))
        if s == "weekday" { self.init(unit: .week, weekdays: Self.weekdaySet, whenDone: whenDone); return }
        if s == "weekend" || s == "weekend day" { self.init(unit: .week, weekdays: Self.weekendSet, whenDone: whenDone); return }
        // "every Monday, Thursday" / "every monday and friday"
        if let days = Self.days(in: s) { self.init(unit: .week, weekdays: days, whenDone: whenDone); return }
        var words = s.split(separator: " ").map(String.init)
        var interval = 1
        if let n = words.first.flatMap(Int.init) { interval = n; words.removeFirst() }
        if words.first == "other" { interval = 2; words.removeFirst() }
        guard let unitWord = words.first else { return nil }
        let unit: Unit
        switch unitWord {
        case "day", "days": unit = .day
        case "week", "weeks": unit = .week
        case "month", "months": unit = .month
        default: return nil
        }
        words.removeFirst()
        var weekdays: Set<Int> = []
        if unit == .week, words.first == "on" {
            guard let days = Self.days(in: words.dropFirst().joined(separator: " ")) else { return nil }
            weekdays = days
        } else if !words.isEmpty {
            return nil
        }
        self.init(interval: interval, unit: unit, weekdays: weekdays, whenDone: whenDone)
    }

    /// "monday, thursday" / "monday and friday" → [1, 4]; nil unless every word is a day name.
    static func days(in s: String) -> Set<Int>? {
        let parts = s.replacingOccurrences(of: " and ", with: ",").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !parts.isEmpty else { return nil }
        var out: Set<Int> = []
        for p in parts {
            guard let d = dayNames[p] ?? dayNames.first(where: { $0.key.hasPrefix(p) && p.count >= 3 })?.value else { return nil }
            out.insert(d)
        }
        return out
    }

    /// The canonical text written after `🔁`.
    public var text: String {
        let done = whenDone ? " when done" : ""
        if unit == .week, interval == 1, weekdays == Self.weekdaySet { return "every weekday" + done }
        if unit == .week, interval == 1, weekdays == Self.weekendSet { return "every weekend" + done }
        let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let base = interval == 1 ? "every \(unit.rawValue)" : "every \(interval) \(unit.rawValue)s"
        let on = weekdays.isEmpty ? "" : " on " + weekdays.sorted().map { names[$0 - 1] }.joined(separator: ", ")
        return base + on + done
    }

    /// The first day after `day` that the rule lands on, counting from `day` as an occurrence.
    public func next(after day: String, calendar: DayCalendar) -> String? {
        guard let start = calendar.startOfDay(day) else { return nil }
        switch unit {
        case .day:
            return calendar.addDays(interval, to: day)
        case .month:
            return calendar.addMonths(interval, to: day)
        case .week:
            guard !weekdays.isEmpty else { return calendar.addDays(7 * interval, to: day) }
            // Later this week, or the first chosen day `interval` weeks on.
            let weekStart = calendar.weekStart(start)
            for offset in 1...(7 * interval + 7) {
                let d = calendar.addDays(offset, to: day)
                guard let date = calendar.startOfDay(d), weekdays.contains(calendar.isoWeekday(date)) else { continue }
                let weeks = calendar.daysBetween(weekStart, calendar.weekStart(date)) / 7
                if weeks % interval == 0 { return d }
            }
            return nil
        }
    }
}
