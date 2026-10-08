import PastelFocusCore
import SwiftUI

/// The plant art for each slot. A theme can draw its own ten (`perTheme`); until the planned
/// redesign every theme uses the shared set.
enum PlantDesigns {
    static let shared: [Slot: [String]] = [
        .a: Sprite.crystalPine, .b: Sprite.lanternFlower, .c: Sprite.fern, .d: Sprite.blossomTree, .e: Sprite.grassTuft,
        .f: Sprite.mushroom, .g: Sprite.cactus, .h: Sprite.sunflower, .i: Sprite.berryBush, .j: Sprite.crystalCluster,
    ]
    static let names: [Slot: String] = [
        .a: "Crystal pine", .b: "Lantern flower", .c: "Fern", .d: "Blossom tree", .e: "Grass tuft",
        .f: "Mushroom", .g: "Cactus", .h: "Sunflower", .i: "Berry bush", .j: "Crystal cluster",
    ]
    /// Theme id → its own designs for some or all slots.
    static let perTheme: [String: [Slot: [String]]] = [:]

    static func sprite(_ slot: Slot, theme: String) -> [String] { perTheme[theme]?[slot] ?? shared[slot]! }
    static func name(_ slot: Slot, theme: String) -> String { names[slot]! }
}

/// Resolves a tag to its plant in the current theme: tag → slot (Tags.md, with any per-theme
/// choice) → that theme's design. Set once at each panel's root, read wherever plants are drawn.
struct PlantArt {
    var registry = TagRegistry()
    var theme = ""

    func slot(forTag tag: String?) -> Slot { registry.slot(for: tag, theme: theme) }
    func sprite(forTag tag: String?) -> [String] { PlantDesigns.sprite(slot(forTag: tag), theme: theme) }
}

private struct PlantArtKey: EnvironmentKey { static let defaultValue = PlantArt() }

extension EnvironmentValues {
    var plantArt: PlantArt {
        get { self[PlantArtKey.self] }
        set { self[PlantArtKey.self] = newValue }
    }
}
