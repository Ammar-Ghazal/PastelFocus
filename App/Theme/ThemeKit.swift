import PastelFocusCore
import SwiftUI

extension Color {
    init(_ c: RGBA) { self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a) }

    init(hex: UInt32, opacity: Double = 1) { self.init(RGBA(hex: hex, alpha: opacity)) }
}

/// SwiftUI view of a theme + palette: the tokens views draw with.
struct Theme {
    let definition: ThemeDefinition
    let palette: Palette

    init(_ definition: ThemeDefinition, _ palette: Palette) {
        self.definition = definition
        self.palette = palette
    }

    init(_ selection: ThemeSelection) {
        let (d, p) = ThemeCatalog.resolve(selection)
        self.init(d, p)
    }

    static let standard = Theme(.default)

    var scene: SceneKind { definition.scene }
    var isNight: Bool { palette.isDark }

    var surface: Color { Color(palette.surface) }
    var glassTint: Color { Color(palette.glass) }
    var elevated: Color { Color(palette.elevated) }
    var highlight: Color { Color(palette.highlight) }
    var track: Color { Color(palette.track) }
    var border: Color { Color(palette.border) }
    var borderActive: Color { Color(palette.borderActive) }
    var textPrimary: Color { Color(palette.textPrimary) }
    var textSecondary: Color { Color(palette.textSecondary) }
    var textTertiary: Color { Color(palette.textTertiary) }
    var accentLight: Color { Color(palette.accentLight) }
    var accent: Color { Color(palette.accent) }
    var accentStrong: Color { Color(palette.accentStrong) }
    var onAccent: Color { Color(palette.onAccent) }
    var tagFocus: Color { Color(palette.tagFocus) }
    var tagHealth: Color { Color(palette.tagHealth) }
    var tagLater: Color { Color(palette.tagLater) }
    var tagHigh: Color { Color(palette.tagHigh) }
    var tagLearning: Color { Color(palette.tagLearning) }
    var sceneTop: Color { Color(palette.sceneTop) }
    var sceneBottom: Color { Color(palette.sceneBottom) }
    var ground: Color { Color(palette.ground) }
    var groundShade: Color { Color(palette.groundShade) }
    var glow: Color { Color(palette.glow) }
    var particle: Color { Color(palette.particle) }

    /// Large display text (panel titles) in the theme's typeface.
    func titleFont(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: design)
    }

    var design: Font.Design {
        switch definition.font {
        case .standard: .default
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        }
    }

    /// Tag colour by category/priority word.
    func tagColor(_ tag: String) -> Color {
        switch tag.lowercased() {
        case "urgent", "high": tagHigh
        case "focus", "coding", "career": tagFocus
        case "health": tagHealth
        case "later": tagLater
        case "learning": tagLearning
        default: accent
        }
    }
}

private struct ThemeKey: EnvironmentKey { static let defaultValue = Theme.standard }
private struct SnapshotKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
    /// True when rendering offscreen PNGs, where AppKit-backed views can't be drawn.
    var snapshotMode: Bool {
        get { self[SnapshotKey.self] }
        set { self[SnapshotKey.self] = newValue }
    }
}
