import SwiftUI

private struct AmbientMotionKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    /// Settings → Appearance → Ambient motion. Off (or Reduce Motion) = static scenes only.
    var ambientMotion: Bool {
        get { self[AmbientMotionKey.self] }
        set { self[AmbientMotionKey.self] = newValue }
    }
}

/// Panel background: system blur, the palette's glass tint, the theme's scene art (and ambient
/// motion when allowed), a hairline border and a drag area.
struct GlassBackground: View {
    @Environment(\.theme) var theme
    @Environment(\.snapshotMode) var snapshot
    @Environment(\.ambientMotion) var ambientMotion
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    var radius: CGFloat = 20
    /// How strongly the scene shows through. Text-heavy panels use less so rows stay easy to read.
    var sceneOpacity: Double = 0.55

    private var animate: Bool { ambientMotion && !reduceMotion && !snapshot }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            if snapshot { shape.fill(theme.surface) } else { VisualEffect().clipShape(shape) }
            shape.fill(theme.glassTint)
            SceneArt(theme: theme, includeMovers: !animate).opacity(sceneOpacity).clipShape(shape)
            if animate { AmbientScene(theme: theme).opacity(min(1, sceneOpacity * 1.5)).clipShape(shape) }
            shape.strokeBorder(theme.border, lineWidth: 1)
            // Any empty part of the panel (header, padding, gaps) drags the window.
            if !snapshot { WindowDragArea() }
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
