import Foundation

/// One of the ten plant designs every theme provides (A–J). A tag picks a slot once; each theme
/// draws its own plant for that slot, so tags never need to know which themes exist.
public enum Slot: Int, CaseIterable, Codable, Sendable, Comparable {
    case a, b, c, d, e, f, g, h, i, j

    public var letter: String { String(Character(UnicodeScalar(UInt8(65 + rawValue)))) }

    public init?(letter: String) {
        guard let c = letter.trimmingCharacters(in: .whitespaces).uppercased().unicodeScalars.first,
              letter.trimmingCharacters(in: .whitespaces).count == 1,
              let s = Slot(rawValue: Int(c.value) - 65) else { return nil }
        self = s
    }

    public static func < (a: Slot, b: Slot) -> Bool { a.rawValue < b.rawValue }
}

/// A tag the user (or Hermes) puts on task lines, e.g. `#coding`, and the plant it grows.
public struct TagDefinition: Equatable, Sendable, Identifiable {
    /// Lowercased, without `#`.
    public var name: String
    public var slot: Slot
    /// Optional per-theme choice (theme id → slot); most tags have none.
    public var overrides: [String: Slot]

    public var id: String { name }

    public init(name: String, slot: Slot, overrides: [String: Slot] = [:]) {
        self.name = TagRegistry.normalize(name); self.slot = slot; self.overrides = overrides
    }

    public func slot(inTheme themeID: String) -> Slot { overrides[themeID] ?? slot }
}

public enum TagError: Error, Equatable, CustomStringConvertible {
    case invalidName, reserved, exists, inUse(Int)
    public var description: String {
        switch self {
        case .invalidName: return "Tags start with a letter and use letters, numbers, - or /"
        case .reserved: return "#later marks priority, not a kind of work"
        case .exists: return "That tag already exists"
        case .inUse(let n): return "Used by \(n) task\(n == 1 ? "" : "s"); rename it instead"
        }
    }
}

/// The tag list, kept in the vault as `PastelFocus/Tags.md` so Hermes reuses the same tags.
public struct TagRegistry: Equatable, Sendable {
    public private(set) var tags: [TagDefinition]

    /// Tags that mark priority or scheduling, not a kind of work. They never choose a plant.
    public static let reserved: Set<String> = ["later"]
    /// Plants for tasks without a tag, and for tags no longer in the list.
    public static let fallback: Slot = .a

    public init(_ tags: [TagDefinition] = []) { self.tags = tags }

    public static func normalize(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces).lowercased()
        while t.hasPrefix("#") { t.removeFirst() }
        return t
    }

    public static func isValid(_ name: String) -> Bool {
        name.range(of: #"^[a-z][\w/-]*$"#, options: .regularExpression) != nil
    }

    public func tag(named name: String) -> TagDefinition? {
        let n = Self.normalize(name)
        return tags.first { $0.name == n }
    }

    public func slot(for tag: String?, theme: String) -> Slot {
        tag.flatMap { self.tag(named: $0) }?.slot(inTheme: theme) ?? Self.fallback
    }

    /// Adds tags not yet listed, each on the slot used least so far (ties → earliest letter), so new
    /// tags spread across the designs. Returns whether anything was added.
    @discardableResult
    public mutating func adopt(_ names: [String]) -> Bool {
        var added = false
        for raw in names {
            let n = Self.normalize(raw)
            guard Self.isValid(n), !Self.reserved.contains(n), tag(named: n) == nil else { continue }
            tags.append(TagDefinition(name: n, slot: leastUsedSlot()))
            added = true
        }
        return added
    }

    public func leastUsedSlot() -> Slot {
        let used = Dictionary(grouping: tags, by: \.slot).mapValues(\.count)
        return Slot.allCases.min { (used[$0] ?? 0, $0.rawValue) < (used[$1] ?? 0, $1.rawValue) }!
    }

    public mutating func add(_ name: String) throws {
        let n = Self.normalize(name)
        guard Self.isValid(n) else { throw TagError.invalidName }
        guard !Self.reserved.contains(n) else { throw TagError.reserved }
        guard tag(named: n) == nil else { throw TagError.exists }
        tags.append(TagDefinition(name: n, slot: leastUsedSlot()))
    }

    public mutating func setSlot(_ slot: Slot, for name: String) {
        guard let i = index(name) else { return }
        tags[i].slot = slot
    }

    /// `nil` clears the override, so the theme uses the tag's usual slot.
    public mutating func setOverride(_ slot: Slot?, for name: String, theme: String) {
        guard let i = index(name) else { return }
        tags[i].overrides[theme] = slot
    }

    public mutating func rename(_ old: String, to new: String) throws {
        let n = Self.normalize(new)
        guard let i = index(old) else { return }
        guard Self.isValid(n) else { throw TagError.invalidName }
        guard !Self.reserved.contains(n) else { throw TagError.reserved }
        guard tag(named: n) == nil || n == tags[i].name else { throw TagError.exists }
        tags[i].name = n
    }

    /// Puts `names` (some of the tags, e.g. the ones shown as Today pills) in this order, in the
    /// places they already hold, so tags left out keep their positions. Unknown names are ignored.
    public mutating func reorder(_ names: [String]) {
        var wanted: [String] = []
        for n in names.map(Self.normalize) where tag(named: n) != nil && !wanted.contains(n) { wanted.append(n) }
        let positions = tags.indices.filter { wanted.contains(tags[$0].name) }
        let defs = wanted.compactMap { tag(named: $0) }
        for (p, d) in zip(positions, defs) { tags[p] = d }
    }

    /// List-style move (Settings → Tags): the tags at `source` go before the tag now at `destination`.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.filter { tags.indices.contains($0) }.map { tags[$0] }
        var rest = tags.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        rest.insert(contentsOf: moving, at: min(rest.count, destination - source.filter { $0 < destination }.count))
        tags = rest
    }

    public mutating func remove(_ name: String) {
        if let i = index(name) { tags.remove(at: i) }
    }

    private func index(_ name: String) -> Int? {
        let n = Self.normalize(name)
        return tags.firstIndex { $0.name == n }
    }

    // MARK: Tags.md

    public func markdown() -> String {
        var lines = ["# PastelFocus Tags", "",
                     "_Managed in PastelFocus → Settings → Tags. The first tag on a task line decides the plant it grows (#later marks priority and is skipped). Row order is the order of the tag pills in the Today panel. Hermes: reuse these tags when writing tasks; new tags are added here automatically._",
                     "", "| Tag | Slot | Theme overrides |", "| --- | --- | --- |"]
        for t in tags {
            let o = t.overrides.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value.letter)" }.joined(separator: ", ")
            lines.append("| #\(t.name) | \(t.slot.letter) |" + (o.isEmpty ? " |" : " \(o) |"))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Reads the table back. Tolerates hand edits: unknown slots fall back, bad rows are skipped.
    public static func parse(_ text: String) -> TagRegistry {
        var out = TagRegistry()
        for line in text.components(separatedBy: "\n") {
            let cells = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 3, cells[1].hasPrefix("#") else { continue }
            let name = normalize(cells[1])
            guard isValid(name), !reserved.contains(name), out.tag(named: name) == nil else { continue }
            var overrides: [String: Slot] = [:]
            if cells.count >= 4 {
                for pair in cells[3].split(separator: ",") {
                    let kv = pair.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
                    if kv.count == 2, let s = Slot(letter: kv[1]), !kv[0].isEmpty { overrides[kv[0]] = s }
                }
            }
            out.tags.append(TagDefinition(name: name, slot: Slot(letter: cells[2]) ?? fallback, overrides: overrides))
        }
        return out
    }
}
