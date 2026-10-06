import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: opacity)
    }
}

/// Design tokens from the spec. Night is the default; Day is the proposed pastel-light theme.
struct Theme {
    let glassTint: Color
    let elevated: Color
    let highlight: Color
    let border: Color
    let borderActive: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let pinkLight: Color
    let pink: Color
    let pinkStrong: Color
    let lavender: Color
    let mint: Color
    let cream: Color
    let coral: Color
    let cyan: Color
    let track: Color
    let onPink: Color
    let isNight: Bool

    static let night = Theme(
        glassTint: Color(hex: 0x0C121F, opacity: 0.78), elevated: Color(hex: 0x1A2032), highlight: Color(hex: 0x493847),
        border: Color.white.opacity(0.08), borderActive: Color(hex: 0xF6A6CF, opacity: 0.38),
        textPrimary: Color(hex: 0xF5EDF6), textSecondary: Color(hex: 0xAAA9BA), textTertiary: Color(hex: 0x727386),
        pinkLight: Color(hex: 0xFFD2E6), pink: Color(hex: 0xF6A6CF), pinkStrong: Color(hex: 0xF28AB8),
        lavender: Color(hex: 0xB9B7FF), mint: Color(hex: 0x91E0BF), cream: Color(hex: 0xF8DFA1), coral: Color(hex: 0xFF8291),
        cyan: Color(hex: 0x8DE4E6), track: Color(hex: 0x303548), onPink: Color(hex: 0x252338), isNight: true)

    static let day = Theme(
        glassTint: Color(hex: 0xFFF8FC, opacity: 0.80), elevated: Color(hex: 0xF6EAF3), highlight: Color(hex: 0xFBDDEB),
        border: Color(hex: 0x3A3346, opacity: 0.08), borderActive: Color(hex: 0xE77FB0, opacity: 0.45),
        textPrimary: Color(hex: 0x3A3346), textSecondary: Color(hex: 0x7A7088), textTertiary: Color(hex: 0x9A90A8),
        pinkLight: Color(hex: 0xFFE3F0), pink: Color(hex: 0xE99BC4), pinkStrong: Color(hex: 0xE77FB0),
        lavender: Color(hex: 0x6E6AD8), mint: Color(hex: 0x3C9C78), cream: Color(hex: 0xB88A1E), coral: Color(hex: 0xD9536A),
        cyan: Color(hex: 0x2E8F99), track: Color(hex: 0xEBDDE7), onPink: Color(hex: 0x3A3346), isNight: false)

    /// Tag colour by category/priority word.
    func tagColor(_ tag: String) -> Color {
        switch tag.lowercased() {
        case "high": return coral
        case "focus", "coding", "career": return lavender
        case "health": return mint
        case "later": return cream
        case "learning": return cyan
        default: return pink
        }
    }
}

private struct ThemeKey: EnvironmentKey { static let defaultValue = Theme.night }

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// Glass panel background: system blur, dark tint, hairline border.
struct GlassBackground: View {
    @Environment(\.theme) var theme
    var radius: CGFloat = 20

    var body: some View {
        ZStack {
            VisualEffect().clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(theme.glassTint)
            RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(theme.border, lineWidth: 1)
        }
    }
}

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Retro RPG-style status chip.
struct TagChip: View {
    @Environment(\.theme) var theme
    let text: String

    var body: some View {
        let c = theme.tagColor(text)
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(c)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 6).fill(c.opacity(theme.isNight ? 0.16 : 0.12)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(c.opacity(0.25), lineWidth: 1))
    }
}

/// Small pixel-font label; falls back to monospaced SF if Pixelify Sans isn't installed.
struct PixelLabel: View {
    @Environment(\.theme) var theme
    let text: String
    var size: CGFloat = 12
    var body: some View {
        Text(text)
            .font(NSFont(name: "PixelifySans-Medium", size: size) != nil ? .custom("PixelifySans-Medium", size: size) : .system(size: size, weight: .medium, design: .monospaced))
            .foregroundStyle(theme.textPrimary)
    }
}
