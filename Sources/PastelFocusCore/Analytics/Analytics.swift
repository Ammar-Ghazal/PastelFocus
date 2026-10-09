import Foundation

/// A detected pattern plus the numbers behind it.
public struct Insight: Codable, Sendable, Equatable {
    public var kind: String
    /// What the pattern is about, e.g. "category:coding", "hours:14-16", "session#4+".
    public var scope: String
    public var title: String
    /// Plain sentence with real numbers, shown behind "Why?".
    public var evidence: String
    public var value: Double
    public var baseline: Double?
    public var sampleN: Int
    public var days: Int
    public var windowDays: Int
    public var computedAt: Date
}

/// Thresholds a difference has to clear before it is called a pattern (spec section 7).
public struct InsightThresholds: Sendable {
    public var minGroup = 12
    public var minBaseline = 12
    public var minDistinctDays = 7
    public var minRateRatio = 1.5
    public var minDurationGap = 0.20
    /// Suggest shorter sessions when the median focus span is this far below the preset.
    public var shorterSessionGap = 0.15
    public var minFocusSpanSessions = 15
    public var minNSDR = 6
    public var postponeCount = 3
    /// z for an 80% interval.
    public var z = 1.2816
    public init() {}
}

/// Wilson score interval for a proportion.
public func wilson(_ successes: Int, _ n: Int, z: Double) -> (low: Double, high: Double) {
    guard n > 0 else { return (0, 1) }
    let p = Double(successes) / Double(n), nn = Double(n), z2 = z * z
    let centre = (p + z2 / (2 * nn)) / (1 + z2 / nn)
    let half = z * sqrt(p * (1 - p) / nn + z2 / (4 * nn * nn)) / (1 + z2 / nn)
    return (max(0, centre - half), min(1, centre + half))
}

func median(_ xs: [Double]) -> Double {
    let s = xs.sorted()
    guard !s.isEmpty else { return 0 }
    return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
}

func quantile(_ xs: [Double], _ q: Double) -> Double {
    let s = xs.sorted()
    guard !s.isEmpty else { return 0 }
    let pos = q * Double(s.count - 1)
    let lo = Int(pos.rounded(.down)), hi = Int(pos.rounded(.up))
    return s[lo] + (s[hi] - s[lo]) * (pos - Double(lo))
}

func pct(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }

public struct AnalyticsInput {
    public var sessions: [SessionRecord]
    public var events: [TaskEvent]
    public var tasks: [TaskItem]
    public init(sessions: [SessionRecord], events: [TaskEvent], tasks: [TaskItem]) {
        self.sessions = sessions; self.events = events; self.tasks = tasks
    }
}

/// Plain statistics over the logs. No model, no guessing: every insight carries its sample size.
public struct AnalyticsEngine {
    public let calendar: DayCalendar
    public var thresholds = InsightThresholds()

    public init(calendar: DayCalendar) { self.calendar = calendar }

    public func insights(_ input: AnalyticsInput, now: Date) -> [Insight] {
        let recent = focusSessions(input.sessions, within: 28, of: now)
        let long = focusSessions(input.sessions, within: 90, of: now)
        var out: [Insight] = []
        out += focusSpan(recent, now: now)
        out += groupRates(recent, now: now, window: 28, kind: "category", scope: { $0.category.map { "category:\($0)" } },
                          label: { "\($0.dropFirst("category:".count)) tasks" })
        out += groupRates(recent, now: now, window: 28, kind: "time_of_day", scope: { s in
            let h = calendar.hour(s.startedAt) / 2 * 2
            return "hours:\(h)-\(h + 2)"
        }, label: { scope in
            let parts = scope.dropFirst("hours:".count).split(separator: "-").compactMap { Int($0) }
            return "sessions started \(Self.clock(parts[0]))–\(Self.clock(parts[1]))"
        })
        out += fatigue(recent, now: now)
        out += weekdays(long, now: now)
        out += pausePosition(recent, now: now)
        out += postponed(input, now: now)
        out += categoryTimeOfDay(long, now: now)
        out += nsdrEffect(input.sessions.filter { now.timeIntervalSince($0.startedAt) <= 90 * 86_400 }, now: now)
        return out
    }

    func focusSessions(_ s: [SessionRecord], within days: Int, of now: Date) -> [SessionRecord] {
        s.filter { $0.kind == .focus && now.timeIntervalSince($0.startedAt) <= Double(days) * 86_400 && $0.startedAt <= now }
    }

    func distinctDays(_ s: [SessionRecord]) -> Int { Set(s.map { calendar.day($0.startedAt) }).count }

    static func clock(_ h: Int) -> String {
        let h12 = h % 12 == 0 ? 12 : h % 12
        return "\(h12) \(h < 12 || h == 24 ? "AM" : "PM")"
    }

    // MARK: Individual patterns

    func focusSpan(_ s: [SessionRecord], now: Date) -> [Insight] {
        let spans = s.compactMap(\.secondsToFirstInterruption).map { Double($0) / 60 }
        guard spans.count >= thresholds.minFocusSpanSessions else { return [] }
        let m = median(spans), q1 = quantile(spans, 0.25), q3 = quantile(spans, 0.75)
        // Stopwatch sessions have no plan to compare against.
        let planned = median(s.filter { !$0.isStopwatch }.map { Double($0.plannedS) / 60 })
        var title = "Focus usually breaks after about \(Int(m.rounded())) min"
        if planned > 0, (planned - m) / planned >= thresholds.shorterSessionGap {
            title += "; try \(max(15, Int((m / 5).rounded(.down)) * 5))-min sessions"
        }
        return [Insight(kind: "focus_span", scope: "all", title: title,
                        evidence: "Over the last 4 weeks, \(spans.count) sessions had their first pause or stop at a median of \(Int(m.rounded())) min (middle half \(Int(q1.rounded()))–\(Int(q3.rounded())) min), against a planned \(Int(planned.rounded())) min.",
                        value: m, baseline: planned, sampleN: spans.count, days: distinctDays(s), windowDays: 28, computedAt: now)]
    }

    /// Compares the interruption rate of each group against everything else.
    func groupRates(_ s: [SessionRecord], now: Date, window: Int, kind: String,
                    scope: (SessionRecord) -> String?, label: (String) -> String) -> [Insight] {
        var groups: [String: [SessionRecord]] = [:]
        for x in s { if let k = scope(x) { groups[k, default: []].append(x) } }
        var out: [Insight] = []
        for (key, g) in groups.sorted(by: { $0.key < $1.key }) {
            let rest = s.filter { scope($0) != key }
            guard let ins = compareRates(group: g, baseline: rest, now: now, window: window, kind: kind, scope: key, label: label(key)) else { continue }
            out.append(ins)
        }
        return out
    }

    func compareRates(group g: [SessionRecord], baseline b: [SessionRecord], now: Date, window: Int,
                      kind: String, scope: String, label: String) -> Insight? {
        let t = thresholds
        guard g.count >= t.minGroup, b.count >= t.minBaseline, distinctDays(g) >= t.minDistinctDays else { return nil }
        let gi = g.filter { $0.outcome.isInterrupted }.count, bi = b.filter { $0.outcome.isInterrupted }.count
        let gr = Double(gi) / Double(g.count), br = Double(bi) / Double(b.count)
        let gw = wilson(gi, g.count, z: t.z), bw = wilson(bi, b.count, z: t.z)
        let worse = gr >= br * t.minRateRatio && gw.low > bw.high
        let better = br >= gr * t.minRateRatio && bw.low > gw.high
        guard worse || better else { return nil }
        let title = worse ? "More interruptions in \(label)" : "Fewer interruptions in \(label)"
        return Insight(kind: kind, scope: scope, title: title,
                       evidence: "In the last \(window / 7) weeks, \(label) were interrupted \(gi) of \(g.count) times (\(pct(gr))), vs \(pct(br)) for other sessions (\(bi) of \(b.count)).",
                       value: gr, baseline: br, sampleN: g.count, days: distinctDays(g), windowDays: window, computedAt: now)
    }

    /// Is the Nth session of a day more fragile than earlier ones? Picks the N with the clearest drop.
    func fatigue(_ s: [SessionRecord], now: Date) -> [Insight] {
        var index: [String: Int] = [:]
        var numbered: [(SessionRecord, Int)] = []
        for x in s.sorted(by: { $0.startedAt < $1.startedAt }) {
            let d = calendar.day(x.startedAt)
            index[d, default: 0] += 1
            numbered.append((x, index[d]!))
        }
        var best: Insight?
        for n in 2...5 {
            let late = numbered.filter { $0.1 >= n }.map(\.0), early = numbered.filter { $0.1 < n }.map(\.0)
            guard var ins = compareRates(group: late, baseline: early, now: now, window: 28, kind: "fatigue",
                                         scope: "session#\(n)+", label: "focus block \(n) or later in a day"),
                  let base = ins.baseline, ins.value > base else { continue }
            ins.title = "Focus drops from your \(Self.ordinal(n)) block of the day"
            if best == nil || ins.value - base > best!.value - best!.baseline! { best = ins }
        }
        return best.map { [$0] } ?? []
    }

    static func ordinal(_ n: Int) -> String { ["", "1st", "2nd", "3rd", "4th", "5th"][min(n, 5)] }

    func weekdays(_ s: [SessionRecord], now: Date) -> [Insight] {
        let names = ["", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        var minutesByDay: [String: Double] = [:]
        for x in s { minutesByDay[calendar.day(x.startedAt), default: 0] += Double(x.focusedS) / 60 }
        var byWeekday: [Int: [Double]] = [:]
        for (day, m) in minutesByDay {
            guard let d = calendar.startOfDay(day) else { continue }
            byWeekday[calendar.isoWeekday(d), default: []].append(m)
        }
        let eligible = byWeekday.filter { $0.value.count >= 4 }
        guard eligible.count >= 3 else { return [] }
        let means = eligible.mapValues { $0.reduce(0, +) / Double($0.count) }
        let overall = means.values.reduce(0, +) / Double(means.count)
        guard let best = means.max(by: { $0.value < $1.value }), overall > 0,
              (best.value - overall) / overall >= thresholds.minDurationGap else { return [] }
        return [Insight(kind: "weekday", scope: "weekday:\(best.key)", title: "\(names[best.key])s are your most focused day",
                        evidence: "Across \(eligible[best.key]!.count) \(names[best.key])s you averaged \(Int(best.value.rounded())) focused min, vs \(Int(overall.rounded())) min on an average active day.",
                        value: best.value, baseline: overall, sampleN: eligible[best.key]!.count, days: minutesByDay.count, windowDays: 90, computedAt: now)]
    }

    func pausePosition(_ s: [SessionRecord], now: Date) -> [Insight] {
        let withPauses = s.filter { !$0.pauses.isEmpty }
        guard withPauses.count >= thresholds.minFocusSpanSessions else { return [] }
        var bands = [Int](repeating: 0, count: 5)
        var total = 0
        for x in withPauses { for p in x.pauses { bands[min(4, Int(Double(p.atS) / Double(max(1, x.plannedS)) * 5))] += 1; total += 1 } }
        guard let top = bands.enumerated().max(by: { $0.element < $1.element }), Double(top.element) / Double(total) >= 0.4 else { return [] }
        let lo = top.offset * 20, hi = lo + 20
        return [Insight(kind: "pause_position", scope: "band:\(lo)-\(hi)", title: "You tend to pause \(lo)–\(hi)% of the way into a session",
                        evidence: "\(top.element) of \(total) pauses (\(pct(Double(top.element) / Double(total)))) in \(withPauses.count) sessions came \(lo)–\(hi)% of the way through.",
                        value: Double(top.element) / Double(total), baseline: 0.2, sampleN: withPauses.count, days: distinctDays(withPauses), windowDays: 28, computedAt: now)]
    }

    func postponed(_ input: AnalyticsInput, now: Date) -> [Insight] {
        var count: [String: Int] = [:]
        var first: [String: Date] = [:]
        for e in input.events where e.type == .rescheduled {
            count[e.taskId, default: 0] += 1
            first[e.taskId] = min(first[e.taskId] ?? e.at, e.at)
        }
        let open = Dictionary(input.tasks.filter { $0.status.isOpen }.compactMap { t in t.taskID.map { ($0, t) } }, uniquingKeysWith: { a, _ in a })
        return count.filter { $0.value >= thresholds.postponeCount && open[$0.key] != nil }.sorted { $0.key < $1.key }.map { id, n in
            let t = open[id]!
            return Insight(kind: "postponed", scope: "task:\(id)", title: "\"\(t.title)\" keeps getting postponed",
                           evidence: "Moved \(n) times since \(calendar.day(first[id]!)). Consider splitting it or dropping it.",
                           value: Double(n), baseline: nil, sampleN: n, days: 0, windowDays: 90, computedAt: now)
        }
    }

    /// Best 2-hour block per category, by completion rate, against that category's other sessions.
    func categoryTimeOfDay(_ s: [SessionRecord], now: Date) -> [Insight] {
        var out: [Insight] = []
        let byCat = Dictionary(grouping: s.filter { $0.category != nil }, by: { $0.category! })
        for (cat, xs) in byCat.sorted(by: { $0.key < $1.key }) {
            var best: Insight?
            for block in stride(from: 0, to: 24, by: 2) {
                let inBlock = xs.filter { calendar.hour($0.startedAt) / 2 * 2 == block }
                let rest = xs.filter { calendar.hour($0.startedAt) / 2 * 2 != block }
                guard let ins = compareRates(group: inBlock, baseline: rest, now: now, window: 90, kind: "category_time",
                                             scope: "category:\(cat)|hours:\(block)-\(block + 2)",
                                             label: "\(cat) sessions started \(Self.clock(block))–\(Self.clock(block + 2))"),
                      let base = ins.baseline, ins.value < base else { continue }
                if best == nil || ins.value < best!.value { best = ins }
            }
            if var b = best {
                let parts = b.scope.split(separator: ":").last!.split(separator: "-").compactMap { Int($0) }
                b.title = "\(cat.capitalized) work goes best \(Self.clock(parts[0]))–\(Self.clock(parts[1]))"
                out.append(b)
            }
        }
        return out
    }

    /// Next focus session after an NSDR break vs after any other break.
    func nsdrEffect(_ all: [SessionRecord], now: Date) -> [Insight] {
        let sorted = all.sorted { $0.startedAt < $1.startedAt }
        var afterNSDR: [SessionRecord] = [], afterOther: [SessionRecord] = []
        for (i, s) in sorted.enumerated() where s.kind.isBreak {
            guard let next = sorted[(i + 1)...].first(where: { $0.kind == .focus }),
                  next.startedAt.timeIntervalSince(s.endedAt) <= 30 * 60 else { continue }
            if s.kind == .nsdr { afterNSDR.append(next) } else { afterOther.append(next) }
        }
        guard afterNSDR.count >= thresholds.minNSDR, afterOther.count >= thresholds.minNSDR else { return [] }
        let a = Double(afterNSDR.filter { $0.outcome.isInterrupted }.count) / Double(afterNSDR.count)
        let b = Double(afterOther.filter { $0.outcome.isInterrupted }.count) / Double(afterOther.count)
        let helps = a < b
        return [Insight(kind: "nsdr", scope: "nsdr", title: helps ? "NSDR breaks are followed by steadier sessions" : "NSDR breaks don't seem to help yet",
                        evidence: "Sessions after an NSDR break were interrupted \(pct(a)) of the time (\(afterNSDR.count) sessions), vs \(pct(b)) after other breaks (\(afterOther.count)).",
                        value: a, baseline: b, sampleN: afterNSDR.count, days: 0, windowDays: 90, computedAt: now)]
    }
}
