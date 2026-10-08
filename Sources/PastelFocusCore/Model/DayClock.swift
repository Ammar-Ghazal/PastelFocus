import Foundation

/// Abstracts "now" so the timer and analytics can be tested with fixed times.
public protocol Clock: Sendable {
    func now() -> Date
}

public struct SystemClock: Clock {
    public init() {}
    public func now() -> Date { Date() }
}

/// Converts instants to local calendar days ("2026-10-07"), hours and weekdays.
public struct DayCalendar: Sendable {
    public let timeZone: TimeZone
    private let calendar: Calendar

    public init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.firstWeekday = 2 // ISO weeks start on Monday
        cal.minimumDaysInFirstWeek = 4
        self.calendar = cal
    }

    public func day(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    public func month(_ date: Date) -> String { String(day(date).prefix(7)) }

    /// ISO week label, e.g. "2026-W41".
    public func isoWeek(_ date: Date) -> String {
        let c = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", c.yearForWeekOfYear!, c.weekOfYear!)
    }

    public func startOfDay(_ day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    public func addDays(_ n: Int, to day: String) -> String {
        guard let d = startOfDay(day), let r = calendar.date(byAdding: .day, value: n, to: d) else { return day }
        return self.day(r)
    }

    public func hour(_ date: Date) -> Int { calendar.component(.hour, from: date) }
    public func minuteOfDay(_ date: Date) -> Int { hour(date) * 60 + calendar.component(.minute, from: date) }

    /// 1 = Monday … 7 = Sunday.
    public func isoWeekday(_ date: Date) -> Int {
        let w = calendar.component(.weekday, from: date) // 1 = Sunday
        return w == 1 ? 7 : w - 1
    }

    public func timeString(_ date: Date) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour!, c.minute!)
    }

    /// Monday of the ISO week containing `date`.
    public func weekStart(_ date: Date) -> String {
        let back = isoWeekday(date) - 1
        return addDays(-back, to: day(date))
    }

    /// "Tomorrow", a weekday within the coming week ("Friday"), then a short date ("Mon, Oct 19").
    public func relativeDayTitle(_ day: String, from today: String) -> String {
        guard let d = startOfDay(day), let t = startOfDay(today) else { return day }
        let ahead = calendar.dateComponents([.day], from: t, to: d).day ?? 0
        if ahead == 1 { return "Tomorrow" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.timeZone = timeZone
        f.dateFormat = ahead > 1 && ahead < 7 ? "EEEE" : "EEE, MMM d"
        return f.string(from: d)
    }

    public func longDayTitle(_ day: String) -> String {
        guard let d = startOfDay(day) else { return day }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.timeZone = timeZone
        f.dateFormat = "EEEE, MMMM d, yyyy"
        return f.string(from: d)
    }
}

public enum ISO8601 {
    nonisolated(unsafe) static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func string(_ d: Date) -> String { formatter.string(from: d) }
    public static func date(_ s: String) -> Date? { formatter.date(from: s) }
}
