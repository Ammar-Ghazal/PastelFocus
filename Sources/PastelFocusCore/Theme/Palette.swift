import Foundation

/// Every colour the app uses. One palette = one complete, coordinated colour combo.
public struct Palette: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var isDark: Bool

    // Surfaces
    public var surface: RGBA        // opaque panel base
    public var glass: RGBA          // translucent tint laid over the blur and scene
    public var elevated: RGBA       // pills, buttons, menus
    public var highlight: RGBA      // highlighted task row
    public var track: RGBA          // progress track, unchecked rings
    public var border: RGBA
    public var borderActive: RGBA

    // Text
    public var textPrimary: RGBA
    public var textSecondary: RGBA
    public var textTertiary: RGBA

    // Accent family (was "pink")
    public var accentLight: RGBA
    public var accent: RGBA
    public var accentStrong: RGBA
    public var onAccent: RGBA       // text/icons drawn on the accent

    // Semantic tag colours
    public var tagFocus: RGBA
    public var tagHealth: RGBA
    public var tagLater: RGBA
    public var tagHigh: RGBA
    public var tagLearning: RGBA

    // Scene (backdrop art)
    public var sceneTop: RGBA
    public var sceneBottom: RGBA
    public var ground: RGBA
    public var groundShade: RGBA
    public var glow: RGBA
    public var particle: RGBA

    public var swatches: [RGBA] { [sceneTop, surface, accent, accentLight, tagFocus, tagHealth, tagLater, tagHigh, tagLearning] }
}

/// How saturated a generated palette is.
public enum Vibrance: String, Codable, Sendable, CaseIterable {
    case muted, pastel, vivid
    var chroma: Double { switch self { case .muted: 0.045; case .pastel: 0.085; case .vivid: 0.14 } }
}

/// Hues (degrees) for the five tag colours. Defaults keep their meaning readable in any palette:
/// high = warm red, health = green, later = gold, learning = cyan, focus = lavender.
public struct TagHues: Hashable, Sendable {
    public var focus, health, later, high, learning: Double
    public init(focus: Double = 285, health: Double = 160, later: Double = 85, high: Double = 20, learning: Double = 215) {
        self.focus = focus; self.health = health; self.later = later; self.high = high; self.learning = learning
    }
    public static let standard = TagHues()
}

/// A one-line description of a palette; `PaletteBuilder` derives every token from it.
public struct PaletteSpec: Sendable {
    public var name: String
    public var dark: Bool
    public var bg: Double           // background hue
    public var accent: Double       // accent hue
    public var vibrance: Vibrance
    public var tags: TagHues
    public var scene: Double?       // scene/sky hue (defaults near the background hue)
    public var ground: Double       // ground/foliage hue for scene art
    public var bgChroma: Double     // how tinted the background is

    public init(_ name: String, dark: Bool = true, bg: Double, accent: Double, vibrance: Vibrance = .pastel,
                tags: TagHues = .standard, scene: Double? = nil, ground: Double = 150, bgChroma: Double = 0.04) {
        self.name = name; self.dark = dark; self.bg = bg; self.accent = accent; self.vibrance = vibrance
        self.tags = tags; self.scene = scene; self.ground = ground; self.bgChroma = bgChroma
    }
}

public enum PaletteBuilder {
    public static func slug(_ s: String) -> String {
        s.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }.reduce(into: "") { out, ch in
            if !(ch == "-" && out.last == "-") { out.append(ch) }
        }.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// Lightness/chroma ladders differ for dark and light modes; contrast is then enforced.
    public static func build(_ s: PaletteSpec, themeID: String) -> Palette {
        let c = s.vibrance.chroma
        let sceneHue = s.scene ?? (s.bg + 20).truncatingRemainder(dividingBy: 360)
        func col(_ l: Double, _ ch: Double, _ h: Double, _ a: Double = 1) -> RGBA { OKLCH(l, ch, h).rgb(alpha: a) }

        if s.dark {
            let surface = col(0.20, s.bgChroma, s.bg)
            let elevated = col(0.27, s.bgChroma + 0.005, s.bg)
            let text = ColorMath.ensureContrast(OKLCH(0.95, 0.012, s.bg), against: elevated, minimum: 7)
            let text2 = ColorMath.ensureContrast(OKLCH(0.78, 0.025, s.bg), against: surface, minimum: 4.5)
            let text3 = ColorMath.ensureContrast(OKLCH(0.62, 0.025, s.bg), against: surface, minimum: 3)
            let accent = ColorMath.ensureContrast(OKLCH(0.80, c * 1.2, s.accent), against: surface, minimum: 4.5)
            let strong = OKLCH(max(0.62, accent.l - 0.07), c * 1.45, s.accent)
            let onAccent = ColorMath.readableText(on: accent.rgb(), hue: s.accent)
            func tag(_ h: Double) -> RGBA { ColorMath.ensureContrast(OKLCH(0.82, max(0.09, c), h), against: surface, minimum: 4.5).rgb() }
            return Palette(
                id: "\(themeID)/\(slug(s.name))", name: s.name, isDark: true,
                surface: surface, glass: col(0.17, s.bgChroma, s.bg, 0.78), elevated: elevated,
                highlight: col(0.33, 0.05, s.accent), track: col(0.33, s.bgChroma, s.bg),
                border: RGBA(r: 1, g: 1, b: 1, a: 0.08), borderActive: accent.rgb(alpha: 0.38),
                textPrimary: text.rgb(), textSecondary: text2.rgb(), textTertiary: text3.rgb(),
                accentLight: OKLCH(0.90, c * 0.6, s.accent).rgb(), accent: accent.rgb(), accentStrong: strong.rgb(),
                onAccent: onAccent.rgb(),
                tagFocus: tag(s.tags.focus), tagHealth: tag(s.tags.health), tagLater: tag(s.tags.later),
                tagHigh: tag(s.tags.high), tagLearning: tag(s.tags.learning),
                sceneTop: col(0.15, s.bgChroma + 0.02, sceneHue), sceneBottom: col(0.24, s.bgChroma + 0.04, sceneHue + 25),
                ground: col(0.40, 0.07, s.ground), groundShade: col(0.30, 0.06, s.ground),
                glow: col(0.88, c * 0.9, s.accent), particle: col(0.92, c * 0.7, (s.accent + 40).truncatingRemainder(dividingBy: 360)))
        } else {
            let surface = col(0.97, min(0.02, s.bgChroma * 0.5), s.bg)
            let elevated = col(0.93, min(0.03, s.bgChroma * 0.7), s.bg)
            let text = ColorMath.ensureContrast(OKLCH(0.30, 0.03, s.bg), against: elevated, minimum: 7)
            let text2 = ColorMath.ensureContrast(OKLCH(0.50, 0.03, s.bg), against: surface, minimum: 4.5)
            let text3 = ColorMath.ensureContrast(OKLCH(0.62, 0.025, s.bg), against: surface, minimum: 3)
            let accent = ColorMath.ensureContrast(OKLCH(0.66, c * 1.3, s.accent), against: surface, minimum: 3)
            let strong = OKLCH(max(0.45, accent.l - 0.07), c * 1.45, s.accent)
            let onAccent = ColorMath.readableText(on: accent.rgb(), hue: s.accent)
            func tag(_ h: Double) -> RGBA { ColorMath.ensureContrast(OKLCH(0.52, max(0.11, c * 1.2), h), against: surface, minimum: 4.5).rgb() }
            return Palette(
                id: "\(themeID)/\(slug(s.name))", name: s.name, isDark: false,
                surface: surface, glass: col(0.97, min(0.02, s.bgChroma * 0.5), s.bg, 0.82), elevated: elevated,
                highlight: col(0.91, 0.05, s.accent), track: col(0.89, min(0.03, s.bgChroma), s.bg),
                border: text.rgb(alpha: 0.08), borderActive: accent.rgb(alpha: 0.45),
                textPrimary: text.rgb(), textSecondary: text2.rgb(), textTertiary: text3.rgb(),
                accentLight: OKLCH(0.90, c * 0.6, s.accent).rgb(), accent: accent.rgb(), accentStrong: strong.rgb(),
                onAccent: onAccent.rgb(),
                tagFocus: tag(s.tags.focus), tagHealth: tag(s.tags.health), tagLater: tag(s.tags.later),
                tagHigh: tag(s.tags.high), tagLearning: tag(s.tags.learning),
                sceneTop: col(0.94, s.bgChroma + 0.02, sceneHue), sceneBottom: col(0.86, s.bgChroma + 0.05, sceneHue + 25),
                ground: col(0.72, 0.08, s.ground), groundShade: col(0.62, 0.08, s.ground),
                glow: col(0.80, c, s.accent), particle: col(0.70, c, (s.accent + 40).truncatingRemainder(dividingBy: 360)))
        }
    }
}
