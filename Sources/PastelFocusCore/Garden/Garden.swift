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
    /// Grid cell on the island (0..<Garden.columns, 0..<Garden.rows).
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

    /// Cells kept free for the landmark so plants never cover it.
    public var cells: [(Int, Int)] {
        switch self {
        case .path: return [(0, 3), (1, 3), (2, 3)]
        case .pond: return [(9, 4), (10, 4), (9, 5), (10, 5)]
        case .stoneLantern: return [(5, 1)]
        case .redBridge: return [(8, 4)]
        case .smallHouse: return [(2, 0), (3, 0)]
        case .waterfall: return [(11, 0), (11, 1)]
        }
    }
}

public struct Island: Sendable, Equatable {
    public var week: String
    public var items: [GardenItem]
    public var fireflies: Int
}

public struct Garden: Sendable, Equatable {
    public static let columns = 12
    public static let rows = 6

    public var islands: [Island]
    public var goodDays: Int
    public var currentRun: Int
    public var landmarks: [Landmark]
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
    /// Builds every week's island from the logs. Pure function: same logs → same garden.
    public static func build(sessions: [SessionRecord], events: [TaskEvent], calendar: DayCalendar, now: Date) -> Garden {
        let rollups = Rollups.build(sessions: sessions, events: events, calendar: calendar)
        let (good, run) = progress(rollups: rollups, calendar: calendar, today: calendar.day(now))
        let landmarks = Landmark.allCases.filter { good >= $0.goodDays }
        let reserved = Set(landmarks.flatMap { $0.cells.map { "\($0.0),\($0.1)" } })

        // Sort by time, then id, so ties always place in the same order.
        let ordered = sessions.sorted { ($0.startedAt, $0.id) < ($1.startedAt, $1.id) }
        let byWeek = Dictionary(grouping: ordered, by: { calendar.isoWeek($0.startedAt) })
        let doneByWeek = Dictionary(grouping: events.filter { $0.type == .completed }, by: { calendar.isoWeek($0.at) })
        let weeks = Set(byWeek.keys).union(doneByWeek.keys).sorted()

        let islands = weeks.map { week -> Island in
            var occupied = reserved
            var items: [GardenItem] = []
            for s in byWeek[week] ?? [] {
                guard var item = item(for: s, events: events, now: now, calendar: calendar) else { continue }
                var rng = SeededRandom(seed: stableHash(s.id))
                var placed = false
                for _ in 0..<200 {
                    let x = Int.random(in: 0..<Garden.columns, using: &rng), y = Int.random(in: 0..<Garden.rows, using: &rng)
                    if occupied.insert("\(x),\(y)").inserted { item.x = x; item.y = y; placed = true; break }
                }
                if placed { items.append(item) } // a full island simply stops growing
            }
            return Island(week: week, items: items, fireflies: doneByWeek[week]?.count ?? 0)
        }
        return Garden(islands: islands, goodDays: good, currentRun: run, landmarks: landmarks)
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
    static func progress(rollups: [String: DailyRollup], calendar: DayCalendar, today: String) -> (goodDays: Int, run: Int) {
        let good = rollups.values.filter(\.isGoodDay).map(\.day).sorted()
        guard let first = good.first else { return (0, 0) }
        var run = 0, day = first
        var missesInWeek: [String: Int] = [:]
        while day <= today {
            if rollups[day]?.isGoodDay == true {
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
