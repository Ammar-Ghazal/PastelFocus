import Foundation

public enum Species: String, Codable, Sendable, CaseIterable {
    case crystalPine, lanternFlower, fern, blossomTree, grassTuft

    /// Category → species. Edit here to change the mapping.
    public static func forCategory(_ c: String?) -> Species {
        switch c?.lowercased() {
        case "coding", "career": return .crystalPine
        case "learning": return .lanternFlower
        case "health": return .fern
        case "personal": return .blossomTree
        default: return .grassTuft
        }
    }
}

public enum PlantSize: Int, Codable, Sendable, Comparable {
    case sprout, small, medium, large
    public static func < (a: PlantSize, b: PlantSize) -> Bool { a.rawValue < b.rawValue }

    /// Under 20 min sprout · 20–39 small · 40–69 medium · 70+ large.
    public static func forMinutes(_ m: Int) -> PlantSize {
        m >= 70 ? .large : m >= 40 ? .medium : m >= 20 ? .small : .sprout
    }
}

public enum GardenItemKind: String, Codable, Sendable {
    case plant, wilted, richSoil, sleepingCat, ripple
}

public enum Variant: String, Codable, Sendable { case normal, glowing, golden }

public struct GardenItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: GardenItemKind
    public var species: Species?
    public var size: PlantSize?
    public var variant: Variant
    public var day: String
    /// Tile on the plot it's shown in (0..<plot.side each way). 0,0 is the back corner.
    public var x: Int
    public var y: Int
}

public enum Landmark: String, Codable, Sendable, CaseIterable {
    case path, pond, stoneLantern, redBridge, smallHouse, waterfall

    /// Good days needed to unlock.
    public var goodDays: Int {
        switch self {
        case .path: return 3
        case .pond: return 5
        case .stoneLantern: return 7
        case .redBridge: return 14
        case .smallHouse: return 21
        case .waterfall: return 30
        }
    }

    /// Tiles kept free for the landmark on a plot `side` tiles across, so plants never cover it.
    /// Anchored to the plot's edges and centre so they stay put (relatively) as the plot grows.
    public func tiles(side n: Int) -> [GardenTile] {
        let mid = n / 2
        switch self {
        case .path: return (0..<3).map { GardenTile(x: $0, y: n - 1) }
        case .pond: return [GardenTile(x: n - 2, y: mid), GardenTile(x: n - 1, y: mid), GardenTile(x: n - 2, y: mid + 1), GardenTile(x: n - 1, y: mid + 1)]
        case .stoneLantern: return [GardenTile(x: mid, y: 1)]
        case .redBridge: return [GardenTile(x: n - 3, y: mid)]
        case .smallHouse: return [GardenTile(x: 0, y: 0), GardenTile(x: 1, y: 0)]
        case .waterfall: return [GardenTile(x: n - 1, y: 0)]
        }
    }
}

public struct GardenTile: Hashable, Sendable {
    public var x: Int
    public var y: Int
    public init(x: Int, y: Int) { self.x = x; self.y = y }
}

/// Forest-style views of the garden.
public enum GardenPeriod: String, CaseIterable, Sendable {
    case day, week, month

    /// Identifies the period a day falls in: "2026-10-07", "2026-W41" or "2026-10".
    public func key(for day: String, calendar: DayCalendar) -> String {
        switch self {
        case .day: return day
        case .week: return calendar.startOfDay(day).map(calendar.isoWeek) ?? day
        case .month: return String(day.prefix(7))
        }
    }

    /// A day in the period `offset` periods away (negative = earlier).
    public func shift(_ day: String, by offset: Int, calendar: DayCalendar) -> String {
        switch self {
        case .day: return calendar.addDays(offset, to: day)
        case .week: return calendar.addDays(offset * 7, to: day)
        case .month:
            let y = Int(day.prefix(4)) ?? 2000, m = Int(day.dropFirst(5).prefix(2)) ?? 1
            let total = y * 12 + (m - 1) + offset
            return String(format: "%04d-%02d-01", total / 12, total % 12 + 1)
        }
    }
}

/// One square, isometric plot of land holding a period's sessions. It grows (and the view zooms
/// out) as items are added, so it never gets crowded.
public struct GardenPlot: Sendable, Equatable {
    public var period: GardenPeriod
    public var key: String
    /// Tiles along each edge.
    public var side: Int
    public var items: [GardenItem]
    public var landmarks: [Landmark]
    /// One per task finished in the period.
    public var fireflies: Int
}

public struct Garden: Sendable, Equatable {
    /// Every session's item (unplaced; `plot` lays them out).
    public var items: [GardenItem]
    /// Tasks finished per day, for fireflies.
    public var tasksDone: [String: Int]
    public var goodDays: Int
    public var currentRun: Int
    public var landmarks: [Landmark]

    public static let empty = Garden(items: [], tasksDone: [:], goodDays: 0, currentRun: 0, landmarks: [])

    /// Smallest plot, and the share of tiles that may be used before it grows.
    public static let minSide = 4
    static let maxFill = 0.45

    /// Lays out the period containing `day`. Each item has a fixed home, a fraction of the plot taken
    /// from its id, and goes on the free tile nearest that home. Earlier sessions are placed first, so
    /// as the plot grows plants stay near the same relative spot instead of being reshuffled.
    public func plot(_ period: GardenPeriod, containing day: String, calendar: DayCalendar) -> GardenPlot {
        let key = period.key(for: day, calendar: calendar)
        let members = items.filter { period.key(for: $0.day, calendar: calendar) == key }
        let fireflies = tasksDone.filter { period.key(for: $0.key, calendar: calendar) == key }.values.reduce(0, +)
        let side = Self.side(items: members.count, landmarks: landmarks)
        var occupied = Set(landmarks.flatMap { $0.tiles(side: side) })
        var placed: [GardenItem] = []
        for var item in members {
            let home = Self.home(of: item.id)
            guard let tile = Self.nearestFree(to: (home.u * Double(side), home.v * Double(side)), side: side, occupied: occupied) else { break }
            occupied.insert(tile)
            item.x = tile.x; item.y = tile.y
            placed.append(item)
        }
        return GardenPlot(period: period, key: key, side: side, items: placed, landmarks: landmarks, fireflies: fireflies)
    }

    /// An item's preferred spot as fractions (0..<1) of the plot's width and depth.
    public static func home(of id: String) -> (u: Double, v: Double) {
        var rng = SeededRandom(seed: stableHash(id))
        return (Double(rng.next() % 1_000_000) / 1_000_000, Double(rng.next() % 1_000_000) / 1_000_000)
    }

    /// Free tile whose centre is closest to `target` (in tile units); ties go to the lowest y, then x.
    static func nearestFree(to target: (Double, Double), side: Int, occupied: Set<GardenTile>) -> GardenTile? {
        var best: (GardenTile, Double)?
        for y in 0..<side { for x in 0..<side {
            let t = GardenTile(x: x, y: y)
            guard !occupied.contains(t) else { continue }
            let d = pow(Double(x) + 0.5 - target.0, 2) + pow(Double(y) + 0.5 - target.1, 2)
            if best == nil || d < best!.1 { best = (t, d) }
        } }
        return best?.0
    }

    static func side(items: Int, landmarks: [Landmark]) -> Int {
        let floor = landmarks.isEmpty ? minSide : 6 // room for landmarks without overlap
        var n = max(floor, Int(ceil(sqrt(Double(items) / maxFill))))
        // Landmarks take tiles too; grow until the items fit within the fill limit.
        while Double(items + Set(landmarks.flatMap { $0.tiles(side: n) }).count) > Double(n * n) * maxFill + 1 { n += 1 }
        return n
    }
}

/// FNV-1a: a stable hash (Swift's Hasher is randomised per launch, so layouts would reshuffle).
public func stableHash(_ s: String) -> UInt64 {
    var h: UInt64 = 0xcbf29ce484222325
    for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
    return h
}

/// SplitMix64, seeded per session, so every plant always lands on the same cell.
public struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

public enum GardenBuilder {
    /// Builds the garden from the logs. Pure function: same logs → same garden.
    public static func build(sessions: [SessionRecord], events: [TaskEvent], calendar: DayCalendar, now: Date,
                             goodDayMinutes: Int = GoodDay.defaultMinutes) -> Garden {
        let rollups = Rollups.build(sessions: sessions, events: events, calendar: calendar)
        let (good, run) = progress(rollups: rollups, calendar: calendar, today: calendar.day(now), goodDayMinutes: goodDayMinutes)
        // Sort by time, then id, so ties always place in the same order.
        let ordered = sessions.sorted { ($0.startedAt, $0.id) < ($1.startedAt, $1.id) }
        let items = ordered.compactMap { item(for: $0, events: events, now: now, calendar: calendar) }
        var done: [String: Int] = [:]
        for e in events where e.type == .completed { done[calendar.day(e.at), default: 0] += 1 }
        return Garden(items: items, tasksDone: done, goodDays: good, currentRun: run,
                      landmarks: Landmark.allCases.filter { good >= $0.goodDays })
    }

    static func item(for s: SessionRecord, events: [TaskEvent], now: Date, calendar: DayCalendar) -> GardenItem? {
        let day = calendar.day(s.startedAt)
        switch s.kind {
        case .nsdr: return GardenItem(id: s.id, kind: .sleepingCat, species: nil, size: nil, variant: .normal, day: day, x: 0, y: 0)
        case .longBreak: return GardenItem(id: s.id, kind: .ripple, species: nil, size: nil, variant: .normal, day: day, x: 0, y: 0)
        case .shortBreak: return nil
        case .focus: break
        }
        if s.outcome != .completed {
            let composted = now.timeIntervalSince(s.endedAt) > 86_400
            return GardenItem(id: s.id, kind: composted ? .richSoil : .wilted, species: nil, size: nil, variant: .normal, day: day, x: 0, y: 0)
        }
        let minutes = s.focusedS / 60
        var variant = Variant.normal
        if let id = s.taskId, events.filter({ $0.taskId == id && $0.type == .rescheduled && $0.at < s.startedAt }).count >= 3 {
            variant = .golden
        } else if s.pauses.isEmpty, minutes >= 40 {
            variant = .glowing
        }
        return GardenItem(id: s.id, kind: .plant, species: Species.forCategory(s.category), size: .forMinutes(minutes),
                          variant: variant, day: day, x: 0, y: 0)
    }

    /// Good days unlock landmarks and never reset. The current run allows one missed day per ISO week;
    /// a second miss ends the run (progress pauses, it is not lost).
    static func progress(rollups: [String: DailyRollup], calendar: DayCalendar, today: String,
                         goodDayMinutes: Int = GoodDay.defaultMinutes) -> (goodDays: Int, run: Int) {
        let good = rollups.values.filter { $0.isGoodDay(minFocusedMinutes: goodDayMinutes) }.map(\.day).sorted()
        guard let first = good.first else { return (0, 0) }
        var run = 0, day = first
        var missesInWeek: [String: Int] = [:]
        while day <= today {
            if rollups[day]?.isGoodDay(minFocusedMinutes: goodDayMinutes) == true {
                run += 1
            } else if day < today {
                let week = calendar.isoWeek(calendar.startOfDay(day)!)
                missesInWeek[week, default: 0] += 1
                if missesInWeek[week]! > 1 { run = 0 }
            }
            day = calendar.addDays(1, to: day)
        }
        return (good.count, run)
    }
}
