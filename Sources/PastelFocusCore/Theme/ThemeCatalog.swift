import Foundation

/// Backdrop art + ambient motion. Drawn by the app (animated) and widgets (static).
public enum SceneKind: String, Codable, Sendable, CaseIterable {
    case pastelRetro, deepSpace, enchantedForest, oceanDepths, synthwave, zenPaper
    case cozyAutumn, aurora, desertDusk, sakura, terminal, winter
}

/// Title typography per theme.
public enum FontStyle: String, Codable, Sendable { case standard, rounded, serif, monospaced }

public struct ThemeDefinition: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let summary: String
    public let scene: SceneKind
    public let font: FontStyle
    public let palettes: [Palette]

    public var defaultPalette: Palette { palettes[0] }
    public func palette(_ id: String?) -> Palette? { palettes.first { $0.id == id } }
}

/// What the user picked. Stored in settings and shared with the widgets.
public struct ThemeSelection: Codable, Hashable, Sendable {
    public var themeID: String
    public var paletteID: String
    public init(themeID: String, paletteID: String) { self.themeID = themeID; self.paletteID = paletteID }
    public static let `default` = ThemeSelection(themeID: "pastel-retro", paletteID: "pastel-retro/midnight-blossom")
}

public enum ThemeCatalog {
    /// Resolves a selection, falling back to the theme's first palette, then to the default theme.
    public static func resolve(_ s: ThemeSelection) -> (ThemeDefinition, Palette) {
        let theme = all.first { $0.id == s.themeID } ?? all[0]
        return (theme, theme.palette(s.paletteID) ?? theme.defaultPalette)
    }

    public static func theme(_ id: String) -> ThemeDefinition? { all.first { $0.id == id } }

    public static var allPalettes: [Palette] { all.flatMap(\.palettes) }

    // MARK: Catalogue

    public static let all: [ThemeDefinition] = [
        make("pastel-retro", "Pastel Retro", "Dark glass, dusty pastels and pixel sparkles — the original look.", .pastelRetro, .standard,
             fixed: [Legacy.midnightBlossom, Legacy.morningBlossom], [
            D("Lavender Haze", 280, 300), D("Mint Arcade", 250, 165), D("Peach Pixel", 260, 40), D("Sky Cartridge", 255, 230),
            D("Lemon Drop", 270, 95), D("Coral Reef", 240, 25), D("Lilac Dream", 300, 320), D("Seafoam Night", 220, 180),
            D("Cotton Candy", 290, 350, .vivid), D("Grape Soda", 300, 290, .vivid), D("Bubblegum", 330, 345),
            D("Matcha Latte", 140, 130, .muted), D("Strawberry Milk", 350, 10),
            L("Pastel Pop", 330, 340), L("Mint Chip", 160, 165), L("Lavender Fields", 290, 295), L("Peach Sorbet", 50, 40),
            L("Sky Taffy", 230, 235), L("Lemon Meringue", 95, 85),
        ]),
        make("deep-space", "Deep Space", "Twinkling stars over a slowly orbiting solar system.", .deepSpace, .standard, [
            D("Nebula Pink", 270, 340, ground: 30), D("Cosmic Teal", 250, 190, ground: 40), D("Supernova", 280, 30, .vivid, ground: 220),
            D("Saturn Gold", 260, 80, ground: 60), D("Ion Blue", 255, 240, .vivid, ground: 20), D("Andromeda", 290, 300, ground: 200),
            D("Red Dwarf", 20, 25, .muted, ground: 30), D("Event Horizon", 270, 270, .muted, ground: 300, bgChroma: 0.02),
            D("Pulsar Mint", 240, 160, ground: 330), D("Comet Tail", 230, 200, ground: 50), D("Mars Rover", 30, 40, ground: 35),
            D("Neptune", 245, 230, ground: 230), D("Galactic Violet", 300, 285, .vivid, ground: 60), D("Stardust", 260, 60, .muted, ground: 40),
            D("Lunar Silver", 250, 250, .muted, ground: 250, bgChroma: 0.015), D("Quasar", 280, 320, .vivid, ground: 180),
            D("Orion", 235, 210, ground: 20), D("Celestial Rose", 320, 355, ground: 200), D("Solar Flare", 15, 50, .vivid, ground: 30),
            L("Daylight Observatory", 230, 250, ground: 30), L("Moon Dust", 260, 290, ground: 250),
        ]),
        make("enchanted-forest", "Enchanted Forest", "Mossy greens, misty pines and drifting fireflies.", .enchantedForest, .serif, [
            D("Moss & Firefly", 150, 95, ground: 145), D("Fairy Ring", 160, 320, ground: 150), D("Moonlit Glade", 200, 180, ground: 170),
            D("Elder Grove", 140, 60, .muted, ground: 130), D("Toadstool", 150, 25, ground: 140), D("Will-o'-Wisp", 190, 200, .vivid, ground: 175),
            D("Fern Hollow", 145, 140, ground: 145), D("Bluebell Wood", 170, 270, ground: 155), D("Amber Sap", 120, 70, ground: 125),
            D("Spirit Lantern", 180, 50, ground: 165), D("Mossy Stone", 150, 150, .muted, ground: 140), D("Druid Night", 165, 300, ground: 150),
            D("Wild Thyme", 135, 340, ground: 135), D("Silver Birch", 120, 110, .muted, ground: 115), D("Owl Hour", 220, 85, ground: 160),
            D("Hidden Spring", 185, 170, ground: 170),
            L("Morning Dew", 140, 150, ground: 140), L("Wildflower Meadow", 120, 330, ground: 130), L("Sunlit Clearing", 110, 90, ground: 125),
            L("Herbal Tea", 130, 60, ground: 125), L("Forest Mist", 170, 190, ground: 160),
        ]),
        make("ocean-depths", "Ocean Depths", "Shafts of light and bubbles rising through deep water.", .oceanDepths, .rounded, [
            D("Abyssal", 240, 195, ground: 200), D("Coral Garden", 230, 20, ground: 25), D("Bioluminescent", 220, 175, .vivid, ground: 190),
            D("Kelp Forest", 200, 140, ground: 135), D("Pearl Diver", 235, 300, .muted, ground: 220), D("Lagoon", 200, 190, ground: 180),
            D("Jellyfish", 250, 320, .vivid, ground: 260), D("Sea Glass", 190, 170, .muted, ground: 175), D("Mariana", 255, 230, ground: 240),
            D("Sunken Gold", 230, 85, ground: 70), D("Tidepool", 210, 30, ground: 35), D("Manta", 245, 260, ground: 230),
            D("Anglerfish", 225, 60, .vivid, ground: 210), D("Whale Song", 240, 220, .muted, ground: 225), D("Reef Shark", 215, 200, ground: 205),
            D("Nautilus", 230, 45, ground: 40),
            L("Shallows", 200, 195, ground: 85), L("Seashell", 30, 20, ground: 70), L("Beach Glass", 180, 175, ground: 80),
            L("Sea Foam", 215, 225, ground: 85), L("Lighthouse", 230, 25, ground: 80),
        ]),
        make("synthwave", "Synthwave", "A neon sun sinking behind an endless horizon grid.", .synthwave, .standard, [
            D("Outrun", 290, 330, .vivid, ground: 300), D("Miami Night", 300, 190, .vivid, ground: 320), D("Laser Grid", 280, 300, .vivid, ground: 290),
            D("Sunset Drive", 320, 40, .vivid, ground: 330), D("Chrome Dream", 260, 230, ground: 270), D("Hotline", 330, 345, .vivid, ground: 330),
            D("Vapor Mall", 290, 180, ground: 300), D("Arcade Cabinet", 270, 95, .vivid, ground: 280), D("Cyber Lime", 260, 130, .vivid, ground: 270),
            D("Neon Tokyo", 280, 0, .vivid, ground: 290), D("Retro VHS", 300, 60, ground: 310), D("Pink Horizon", 310, 350, ground: 320),
            D("Midnight Cruise", 250, 280, ground: 260), D("Electric Violet", 285, 290, .vivid, ground: 290), D("Turbo Teal", 240, 185, .vivid, ground: 260),
            D("Cassette", 20, 30, ground: 10), D("Holo Foil", 270, 210, ground: 280), D("Night Drive", 255, 320, ground: 270),
            L("Vaporwave Pastel", 300, 320, ground: 300), L("Aesthetic Mint", 180, 330, ground: 190), L("Memphis", 60, 340, ground: 300),
        ]),
        make("zen-paper", "Zen Paper", "Warm paper, a single ink stroke, and stillness.", .zenPaper, .serif, [
            L("Rice Paper", 80, 30, .muted, bgChroma: 0.03), L("Sumi Ink", 60, 260, .muted), L("Matcha", 110, 135), L("Hinoki", 70, 55),
            L("Indigo Dye", 250, 255), L("Persimmon", 60, 40), L("Stone Garden", 90, 200, .muted), L("Plum Blossom", 20, 350),
            L("Bamboo", 120, 125), L("Celadon", 160, 170, .muted), L("Washi Rose", 20, 10), L("Moss Garden", 130, 140, .muted),
            L("Raked Sand", 75, 60, .muted), L("Camellia", 15, 15),
            D("Night Temple", 60, 40, .muted), D("Charcoal Brush", 70, 70, .muted, bgChroma: 0.015), D("Lantern Glow", 50, 70),
            D("Ink Wash", 250, 220, .muted), D("Koi Pond", 220, 35), D("Tea Ceremony", 110, 120, .muted), D("Moon Viewing", 260, 85, .muted),
        ]),
        make("cozy-autumn", "Cozy Autumn", "Amber light, warm wool and leaves drifting down.", .cozyAutumn, .serif, [
            D("Pumpkin Spice", 40, 50, .vivid, ground: 45), D("Maple Leaf", 30, 25, ground: 35), D("Hearth", 35, 60, ground: 40),
            D("Cider", 50, 70, ground: 55), D("Harvest Moon", 260, 70, ground: 50), D("Woolen Plaid", 20, 15, .muted, ground: 30),
            D("Acorn", 55, 45, .muted, ground: 60), D("Cranberry", 0, 5, ground: 20), D("Chestnut", 40, 35, .muted, ground: 45),
            D("Forest Cabin", 140, 50, ground: 140), D("Candlelight", 60, 75, ground: 55), D("Fig Jam", 330, 340, ground: 30),
            D("Hot Cocoa", 45, 30, .muted, ground: 40), D("Rainy Window", 230, 50, ground: 45),
            L("Golden Hour", 70, 55, ground: 60), L("Apple Orchard", 40, 20, ground: 130), L("Oat Milk", 75, 50, .muted, ground: 70),
            L("Cinnamon", 45, 40, ground: 45), L("Autumn Mist", 90, 30, ground: 80), L("Honey", 85, 75, ground: 75),
            L("Sweater Weather", 30, 350, .muted, ground: 40),
        ]),
        make("aurora", "Aurora", "Ribbons of northern lights over a starlit sky.", .aurora, .standard, [
            D("Borealis", 230, 160, .vivid, ground: 220), D("Polar Violet", 260, 300, .vivid, ground: 240), D("Arctic Teal", 220, 185, ground: 215),
            D("Solar Wind", 240, 130, .vivid, ground: 225), D("Magnetar", 270, 330, ground: 250), D("Glacier", 220, 210, .muted, ground: 210),
            D("Fjord", 210, 170, ground: 200), D("Northern Rose", 280, 350, ground: 250), D("Ice Crystal", 230, 230, ground: 220),
            D("Tundra", 200, 100, .muted, ground: 190), D("Midnight Sun", 250, 60, ground: 230), D("Emerald Veil", 210, 150, .vivid, ground: 210),
            D("Lumen", 245, 260, ground: 235), D("Skyfire", 240, 20, .vivid, ground: 230), D("Spectra", 260, 190, .vivid, ground: 240),
            D("Frost Lilac", 250, 290, ground: 235), D("Starlit Snow", 235, 200, .muted, ground: 225), D("Coronal", 255, 100, .vivid, ground: 240),
            L("Polar Day", 220, 170, ground: 215), L("Frosted Glass", 230, 290, ground: 225), L("Ice Mint", 190, 160, ground: 200),
        ]),
        make("desert-dusk", "Desert Dusk", "Dunes, a low sun and grains of sand on the wind.", .desertDusk, .standard, [
            D("Dune Sunset", 30, 45, ground: 50), D("Mirage", 280, 40, ground: 55), D("Saguaro", 40, 140, ground: 55),
            D("Terracotta", 35, 30, .muted, ground: 40), D("Canyon", 25, 20, .vivid, ground: 35), D("Oasis", 200, 175, ground: 60),
            D("Starry Desert", 260, 70, ground: 55), D("Sandstorm", 60, 75, .muted, ground: 70), D("Copper Mesa", 40, 55, ground: 45),
            D("Desert Rose", 10, 0, ground: 40), D("Scorpion", 50, 85, .vivid, ground: 65), D("Nomad", 45, 210, ground: 60),
            D("Bedouin Indigo", 260, 250, ground: 60), D("Amber Night", 55, 65, ground: 60),
            L("Sahara Noon", 75, 50, ground: 75), L("Adobe", 50, 30, ground: 55), L("Bleached Bone", 80, 70, .muted, ground: 80),
            L("Prickly Pear", 40, 350, ground: 70), L("Turquoise Inlay", 60, 190, ground: 70), L("Sun Baked", 65, 45, ground: 65),
            L("Rose Quartz Sand", 30, 15, ground: 60),
        ]),
        make("sakura", "Sakura Garden", "A blossoming branch and petals on a soft breeze.", .sakura, .rounded, [
            D("Hanami Night", 320, 350, ground: 30), D("Petal Rain", 300, 345, ground: 20), D("Spring Moon", 260, 340, ground: 30),
            D("Plum Wine", 340, 330, .vivid, ground: 20), D("Kimono", 0, 20, ground: 25), D("Moonlit Branch", 270, 310, ground: 20),
            D("Lantern Festival", 340, 50, ground: 25), D("Yozakura", 290, 355, .vivid, ground: 15), D("Matcha Mochi", 140, 345, ground: 30),
            D("Wisteria", 290, 290, ground: 25), D("Shrine Red", 10, 15, .vivid, ground: 30),
            L("Cherry Blossom", 350, 350, ground: 40), L("Sakura Latte", 30, 0, ground: 40), L("Spring Breeze", 320, 330, ground: 35),
            L("Mochi", 340, 345, .muted, ground: 40), L("Peony", 0, 355, .vivid, ground: 35), L("Pink Lemonade", 20, 10, ground: 40),
            L("Blossom & Leaf", 140, 350, ground: 40), L("Lavender Mochi", 290, 300, ground: 35), L("Peach Blossom", 40, 20, ground: 40),
            L("First Bloom", 330, 340, ground: 35),
        ]),
        make("terminal", "Retro Terminal", "CRT scanlines, phosphor glow and a blinking cursor.", .terminal, .monospaced, [
            D("Green Phosphor", 145, 145, .vivid, bgChroma: 0.03), D("Amber CRT", 70, 75, .vivid), D("Ice Blue Terminal", 230, 220, .vivid),
            D("Monochrome", 250, 250, .muted, bgChroma: 0.01), D("Matrix Rain", 150, 150, .vivid, bgChroma: 0.05), D("Hacker Purple", 290, 300, .vivid),
            D("Teletext", 260, 95, .vivid), D("DOS Blue", 260, 200, bgChroma: 0.08), D("Red Alert", 20, 25, .vivid),
            D("Cyan Boot", 210, 195, .vivid), D("Solar Dark", 220, 85), D("Retro Groove", 70, 60, .muted),
            D("Polar Night", 245, 210, .muted), D("Vampire Hour", 285, 320), D("Tokyo Midnight", 265, 250),
            D("Neon Olive", 90, 110, .vivid, bgChroma: 0.02), D("Mocha Cat", 280, 330), D("Atom Night", 250, 230),
            L("Solar Light", 85, 220), L("Paper Terminal", 90, 145, .muted), L("Latte Cat", 280, 300),
        ]),
        make("winter", "Winter Snowfall", "Gentle snow over quiet hills and warm cabin light.", .winter, .rounded, [
            D("Snowfall", 240, 210, ground: 230), D("Frosty Night", 230, 195, ground: 225), D("Holly", 150, 10, ground: 160),
            D("Hot Cider", 30, 40, ground: 220), D("Fireside", 25, 55, ground: 220), D("Pine Cabin", 160, 35, ground: 165),
            D("Northern Star", 245, 85, ground: 235), D("Ice Rink", 220, 230, ground: 215), D("Mistletoe", 140, 350, ground: 150),
            D("Sleigh Bells", 0, 85, ground: 220), D("Blue Hour", 250, 250, ground: 240), D("Candy Cane", 260, 10, .vivid, ground: 235),
            D("Peppermint", 200, 350, ground: 210),
            L("Fresh Powder", 230, 220, ground: 230), L("Snow Day", 220, 10, ground: 225), L("Frosted Pine", 170, 160, ground: 170),
            L("Gingerbread", 50, 35, ground: 220), L("Winter Berry", 240, 350, ground: 230), L("Cashmere", 40, 20, .muted, ground: 220),
            L("Glacier Light", 210, 200, ground: 215), L("Marshmallow", 300, 330, .muted, ground: 230),
        ]),
    ]

    // MARK: Helpers

    static func D(_ name: String, _ bg: Double, _ accent: Double, _ v: Vibrance = .pastel,
                  ground: Double = 150, bgChroma: Double = 0.04) -> PaletteSpec {
        PaletteSpec(name, dark: true, bg: bg, accent: accent, vibrance: v, ground: ground, bgChroma: bgChroma)
    }

    static func L(_ name: String, _ bg: Double, _ accent: Double, _ v: Vibrance = .pastel,
                  ground: Double = 150, bgChroma: Double = 0.04) -> PaletteSpec {
        PaletteSpec(name, dark: false, bg: bg, accent: accent, vibrance: v, ground: ground, bgChroma: bgChroma)
    }

    static func make(_ id: String, _ name: String, _ summary: String, _ scene: SceneKind, _ font: FontStyle,
                     fixed: [(String) -> Palette] = [], _ specs: [PaletteSpec]) -> ThemeDefinition {
        let palettes = fixed.map { $0(id) } + specs.map { PaletteBuilder.build($0, themeID: id) }
        return ThemeDefinition(id: id, name: name, summary: summary, scene: scene, font: font, palettes: palettes)
    }
}

/// The original hand-tuned palettes, kept exactly so existing users see no change.
enum Legacy {
    static func midnightBlossom(_ theme: String) -> Palette {
        Palette(id: "\(theme)/midnight-blossom", name: "Midnight Blossom", isDark: true,
                surface: RGBA(hex: 0x111827), glass: RGBA(hex: 0x0C121F, alpha: 0.78), elevated: RGBA(hex: 0x1A2032),
                highlight: RGBA(hex: 0x493847), track: RGBA(hex: 0x303548), border: RGBA(r: 1, g: 1, b: 1, a: 0.08),
                borderActive: RGBA(hex: 0xF6A6CF, alpha: 0.38),
                textPrimary: RGBA(hex: 0xF5EDF6), textSecondary: RGBA(hex: 0xAAA9BA), textTertiary: RGBA(hex: 0x727386),
                accentLight: RGBA(hex: 0xFFD2E6), accent: RGBA(hex: 0xF6A6CF), accentStrong: RGBA(hex: 0xF28AB8), onAccent: RGBA(hex: 0x252338),
                tagFocus: RGBA(hex: 0xB9B7FF), tagHealth: RGBA(hex: 0x91E0BF), tagLater: RGBA(hex: 0xF8DFA1),
                tagHigh: RGBA(hex: 0xFF8291), tagLearning: RGBA(hex: 0x8DE4E6),
                sceneTop: RGBA(hex: 0x111827), sceneBottom: RGBA(hex: 0x1B2436), ground: RGBA(hex: 0x3E6658),
                groundShade: RGBA(hex: 0x2D4A44), glow: RGBA(hex: 0xFFD2E6), particle: RGBA(hex: 0xF8DFA1))
    }

    static func morningBlossom(_ theme: String) -> Palette {
        func readable(_ hex: UInt32) -> RGBA {
            ColorMath.ensureContrast(OKLCH(RGBA(hex: hex)), against: RGBA(hex: 0xFFF7FB), minimum: 4.5).rgb()
        }
        return Palette(id: "\(theme)/morning-blossom", name: "Morning Blossom", isDark: false,
                surface: RGBA(hex: 0xFFF7FB), glass: RGBA(hex: 0xFFF8FC, alpha: 0.80), elevated: RGBA(hex: 0xF6EAF3),
                highlight: RGBA(hex: 0xFBDDEB), track: RGBA(hex: 0xEBDDE7), border: RGBA(hex: 0x3A3346, alpha: 0.08),
                borderActive: RGBA(hex: 0xE77FB0, alpha: 0.45),
                textPrimary: RGBA(hex: 0x3A3346), textSecondary: RGBA(hex: 0x6F6580), textTertiary: RGBA(hex: 0x8E849C),
                accentLight: RGBA(hex: 0xFFE3F0), accent: RGBA(hex: 0xE99BC4), accentStrong: RGBA(hex: 0xE77FB0), onAccent: RGBA(hex: 0x3A3346),
                // Original tag hues, darkened only as far as needed for 4.5:1 on the light surface.
                tagFocus: readable(0x6E6AD8), tagHealth: readable(0x2F8466), tagLater: readable(0x957014),
                tagHigh: readable(0xC8445B), tagLearning: readable(0x23808A),
                sceneTop: RGBA(hex: 0xF4EEF4), sceneBottom: RGBA(hex: 0xEADFEA), ground: RGBA(hex: 0x9CCB9F),
                groundShade: RGBA(hex: 0x7FAF86), glow: RGBA(hex: 0xE99BC4), particle: RGBA(hex: 0xB88A1E))
    }
}
