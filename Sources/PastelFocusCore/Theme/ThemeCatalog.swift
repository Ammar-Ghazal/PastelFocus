import Foundation

/// Backdrop art + ambient motion. Drawn by the app: static art plus animated ambient layers.
public enum SceneKind: String, Codable, Sendable, CaseIterable {
    case space, cherryBlossom, rainforest, snow, ember, cyberpunk
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

    /// The palette of the requested mode closest in accent colour to `p` (for "match macOS light/dark").
    /// Returns `p` itself if it is already in that mode or the theme has none of the other mode.
    public func counterpart(of p: Palette, dark: Bool) -> Palette {
        guard p.isDark != dark else { return p }
        let target = OKLCH(p.accent)
        return palettes.filter { $0.isDark == dark }.min { OKLCH($0.accent).distance(to: target) < OKLCH($1.accent).distance(to: target) } ?? p
    }
}

/// What the user picked. Stored in settings.
public struct ThemeSelection: Codable, Hashable, Sendable {
    public var themeID: String
    public var paletteID: String
    public init(themeID: String, paletteID: String) { self.themeID = themeID; self.paletteID = paletteID }
    public static let `default` = ThemeSelection(themeID: "cherry-blossom", paletteID: "cherry-blossom/midnight-blossom")
}

public enum ThemeCatalog {
    /// Resolves a selection, falling back to the theme's first palette, then to the default theme.
    /// Resolves a selection for the current system appearance when `matchSystem` is on.
    public static func resolve(_ s: ThemeSelection, matchSystem: Bool, systemDark: Bool) -> (ThemeDefinition, Palette) {
        let (t, p) = resolve(s)
        return (t, matchSystem ? t.counterpart(of: p, dark: systemDark) : p)
    }

    public static func resolve(_ s: ThemeSelection) -> (ThemeDefinition, Palette) {
        let s = migrate(s)
        let theme = all.first { $0.id == s.themeID } ?? all.first { $0.id == ThemeSelection.default.themeID }!
        return (theme, theme.palette(s.paletteID) ?? theme.defaultPalette)
    }

    public static func theme(_ id: String) -> ThemeDefinition? { all.first { $0.id == id } }

    public static var allPalettes: [Palette] { all.flatMap(\.palettes) }

    // MARK: Catalogue

    /// Six themes, each its own scene. Its palettes are colour combos of that scene.
    public static let all: [ThemeDefinition] = [
        make("space", "Space", "Black sky, blinking stars, a solar system and the odd passing spaceship.", .space, .standard, [
            D("Supernova", 280, 30, .vivid, ground: 220), D("Nebula Pink", 270, 340, ground: 30, bgChroma: 0.02),
            D("Cosmic Teal", 250, 190, ground: 40, bgChroma: 0.02), D("Saturn Gold", 260, 80, ground: 60, bgChroma: 0.02),
            D("Ion Blue", 255, 240, .vivid, ground: 20, bgChroma: 0.02), D("Event Horizon", 270, 270, .muted, ground: 300, bgChroma: 0.01),
            L("Daylight Observatory", 230, 250, ground: 30), L("Moon Dust", 260, 290, ground: 250),
        ]),
        make("cherry-blossom", "Cherry Blossom", "A blossoming cherry tree, with petals and leaves falling on the breeze.", .cherryBlossom, .rounded,
             fixed: [Legacy.midnightBlossom, Legacy.morningBlossom], [
            D("Hanami Night", 320, 350, ground: 30), D("Yozakura", 290, 355, .vivid, ground: 15), D("Plum Wine", 340, 330, .vivid, ground: 20),
            D("Spring Moon", 260, 340, ground: 30), L("Cherry Blossom", 350, 350, ground: 40), L("Peach Blossom", 40, 20, ground: 40),
            L("First Bloom", 330, 340, ground: 35),
        ]),
        make("rainforest", "Rainforest", "Layered jungle under sun, dusk or night, with the occasional downpour.", .rainforest, .serif, [
            D("Canopy Night", 150, 95, ground: 145), D("Monsoon", 200, 180, ground: 160), D("Orchid", 160, 320, ground: 150),
            D("Tree Frog", 145, 140, .vivid, ground: 145), D("Macaw", 150, 25, ground: 140),
            L("Morning Mist", 140, 150, ground: 140), L("Sunlit Clearing", 110, 90, ground: 125), L("Rain Lily", 130, 330, ground: 130),
        ]),
        make("snow", "Snow", "Arctic tundra under falling snow: foxes, owls, penguins and a polar bear.", .snow, .rounded, [
            D("Polar Night", 240, 210, ground: 230), D("Aurora", 230, 160, .vivid, ground: 220), D("Northern Star", 245, 85, ground: 235),
            D("Glacier", 220, 210, .muted, ground: 210), D("Frost Lilac", 250, 290, ground: 235),
            L("Fresh Powder", 230, 220, ground: 230), L("Snow Day", 220, 10, ground: 225), L("Ice Mint", 190, 160, ground: 200),
        ]),
        make("ember", "Ember", "A campsite at night: crackling fire, rising embers and fireflies.", .ember, .serif, [
            D("Campfire", 35, 50, .vivid, ground: 45), D("Hearth", 35, 60, ground: 40), D("Firefly", 140, 85, ground: 140),
            D("Starry Camp", 260, 70, ground: 55), D("Cranberry", 0, 5, ground: 20), D("Hot Cocoa", 45, 30, .muted, ground: 40),
            L("Golden Hour", 70, 55, ground: 60), L("Cinnamon", 45, 40, ground: 45),
        ]),
        make("cyberpunk", "Cyberpunk", "A rain-soaked future city: neon signs, lit towers and flying cars.", .cyberpunk, .monospaced, [
            D("Neon Rain", 250, 330, .vivid, ground: 270), D("Replicant", 210, 45, .vivid, ground: 220), D("Tokyo Midnight", 265, 250, ground: 260),
            D("Holo Foil", 270, 210, ground: 280), D("Acid Lime", 260, 130, .vivid, ground: 270), D("Red Alert", 20, 25, .vivid, ground: 20),
            L("Smog Day", 60, 330, ground: 300), L("Chrome", 230, 200, ground: 220),
        ]),
    ]

    /// Themes from before the six (2026-10), and the one each became. A selection of an old theme
    /// keeps its palette when the new theme has one of the same name, otherwise takes the new
    /// theme's first palette.
    static let renamed: [String: String] = [
        "deep-space": "space", "sakura": "cherry-blossom", "pastel-retro": "cherry-blossom", "zen-paper": "cherry-blossom",
        "enchanted-forest": "rainforest", "ocean-depths": "rainforest", "winter": "snow", "aurora": "snow",
        "cozy-autumn": "ember", "desert-dusk": "ember", "synthwave": "cyberpunk", "terminal": "cyberpunk",
    ]

    public static func migrate(_ s: ThemeSelection) -> ThemeSelection {
        guard let newID = renamed[s.themeID], let theme = theme(newID) else { return s }
        let slug = s.paletteID.split(separator: "/").last.map(String.init) ?? ""
        let palette = theme.palette("\(newID)/\(slug)") ?? theme.defaultPalette
        return ThemeSelection(themeID: newID, paletteID: palette.id)
    }

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
