import PastelFocusCore
import SwiftUI

/// Static backdrop art for a theme, drawn once (no per-frame work).
/// `includeMovers` draws the things the app animates (planets, fireflies, petals…) in a fixed pose;
/// the app turns it off and lets Core Animation move them instead.
struct SceneArt: View {
    let theme: Theme
    var includeMovers = true

    var body: some View {
        Canvas { ctx, size in
            var c = ctx
            let rect = CGRect(origin: .zero, size: size)
            c.fill(Path(rect), with: .linearGradient(Gradient(colors: [theme.sceneTop, theme.sceneBottom]),
                                                    startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            SceneArt.draw(theme, in: &c, size: size, movers: includeMovers)
        }
        .allowsHitTesting(false)
    }

    // MARK: Drawing

    static func draw(_ t: Theme, in c: inout GraphicsContext, size s: CGSize, movers: Bool) {
        var rng = SeededRandom(seed: stableHash(t.palette.id))
        func r(_ a: CGFloat, _ b: CGFloat) -> CGFloat { CGFloat.random(in: a...b, using: &rng) }
        func dot(_ x: CGFloat, _ y: CGFloat, _ d: CGFloat, _ col: Color) {
            c.fill(Path(ellipseIn: CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)), with: .color(col))
        }
        func stars(_ n: Int, maxY: CGFloat, _ col: Color) {
            for _ in 0..<n { dot(r(0, s.width), r(0, s.height * maxY), r(0.8, 2.2), col.opacity(Double(r(0.25, 0.85)))) }
        }
        func glowCircle(_ center: CGPoint, _ radius: CGFloat, _ col: Color, _ alpha: Double) {
            c.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                   with: .radialGradient(Gradient(colors: [col.opacity(alpha), col.opacity(0)]), center: center, startRadius: 0, endRadius: radius))
        }
        let night = t.isNight

        switch t.scene {
        case .space:
            // Black sky: stars, a sun with three orbits (the planets move in AmbientScene) and a ringed giant.
            stars(110, maxY: 1, night ? .white : t.textTertiary)
            let sun = CGPoint(x: s.width * 0.86, y: s.height * 0.14)
            glowCircle(sun, min(s.width, s.height) * 0.35, t.glow, 0.32)
            dot(sun.x, sun.y, 16, t.glow)
            for radius in [0.18, 0.30, 0.44] {
                let rr = min(s.width, s.height) * radius
                c.stroke(Path(ellipseIn: CGRect(x: sun.x - rr, y: sun.y - rr * 0.6, width: rr * 2, height: rr * 1.2)),
                         with: .color(t.textTertiary.opacity(0.16)), lineWidth: 0.7)
            }
            let giant = CGPoint(x: s.width * 0.14, y: s.height * 0.8), gr = min(s.width, s.height) * 0.08
            dot(giant.x, giant.y, gr * 2, t.ground.opacity(0.85))
            c.fill(Path(ellipseIn: CGRect(x: giant.x - gr * 0.9, y: giant.y - gr * 0.35, width: gr * 1.8, height: gr * 0.3)), with: .color(t.groundShade.opacity(0.5)))
            c.stroke(Path(ellipseIn: CGRect(x: giant.x - gr * 1.9, y: giant.y - gr * 0.42, width: gr * 3.8, height: gr * 0.84)),
                     with: .color(t.accentLight.opacity(0.55)), lineWidth: 1.6)
            if movers {
                Sprite.draw(Sprite.rocket, in: &c, anchor: CGPoint(x: s.width * 0.5, y: s.height * 0.42), px: 2)
            }

        case .cherryBlossom:
            // Distant hills, then a cherry tree whose canopy fills the top right; petals fall in AmbientScene.
            for (k, y) in [0.80, 0.88].enumerated() {
                var hill = Path(); hill.move(to: CGPoint(x: 0, y: s.height))
                hill.addLine(to: CGPoint(x: 0, y: s.height * y))
                hill.addCurve(to: CGPoint(x: s.width, y: s.height * (y - 0.04)), control1: CGPoint(x: s.width * 0.35, y: s.height * (y - 0.1)),
                              control2: CGPoint(x: s.width * 0.65, y: s.height * (y + 0.06)))
                hill.addLine(to: CGPoint(x: s.width, y: s.height)); hill.closeSubpath()
                c.fill(hill, with: .color((k == 0 ? t.ground : t.groundShade).opacity(night ? 0.35 : 0.45)))
            }
            // The tree is sized by the panel's shorter side, so a tall panel doesn't stretch it.
            let u = min(s.width, s.height * 1.4)
            let base = CGPoint(x: s.width - u * 0.2, y: s.height)
            func at(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: base.x + u * dx, y: base.y - u * dy) }
            var trunk = Path()
            trunk.move(to: base)
            trunk.addCurve(to: at(-0.06, 0.5), control1: at(0.04, 0.2), control2: at(-0.1, 0.32))
            trunk.move(to: at(-0.05, 0.38)); trunk.addQuadCurve(to: at(-0.3, 0.55), control: at(-0.2, 0.4))
            trunk.move(to: at(-0.05, 0.44)); trunk.addQuadCurve(to: at(0.22, 0.62), control: at(0.1, 0.5))
            c.stroke(trunk, with: .color(t.groundShade.opacity(night ? 0.95 : 0.75)), style: StrokeStyle(lineWidth: u * 0.022, lineCap: .round))
            let crown = at(-0.05, 0.58)
            for _ in 0..<18 {
                glowCircle(CGPoint(x: crown.x + r(-u * 0.32, u * 0.3), y: crown.y + r(-u * 0.16, u * 0.12)), r(u * 0.07, u * 0.12), t.accentLight, night ? 0.32 : 0.45)
            }
            for _ in 0..<90 {
                dot(crown.x + r(-u * 0.34, u * 0.32), crown.y + r(-u * 0.17, u * 0.13), r(3, 6.5), [t.accentLight, t.accent, t.accentStrong][Int(r(0, 2.99))].opacity(0.8))
            }
            if movers { for _ in 0..<8 { dot(r(0, s.width), r(s.height * 0.4, s.height), 4, t.accentLight.opacity(0.6)) } }

        case .rainforest:
            // Three layers of jungle, lightest at the back. Light level and rain are set in AmbientScene.
            for layer in 0..<3 {
                // Layers stack from the bottom in fixed steps; tree sizes don't grow with the panel.
                let base = s.height - CGFloat(2 - layer) * 26
                var x: CGFloat = -20
                while x < s.width + 30 {
                    let w = r(40, 70), h = r(70, 150)
                    var tree = Path()
                    tree.addRect(CGRect(x: x - 2, y: base - h + w * 0.4, width: 4, height: h))
                    tree.addEllipse(in: CGRect(x: x - w / 2, y: base - h, width: w, height: w * 0.7))
                    tree.addEllipse(in: CGRect(x: x - w * 0.85, y: base - h + w * 0.25, width: w * 0.95, height: w * 0.6))
                    tree.addEllipse(in: CGRect(x: x - w * 0.1, y: base - h + w * 0.22, width: w * 0.95, height: w * 0.6))
                    c.fill(tree, with: .color(t.groundShade.opacity(0.28 + Double(layer) * 0.22)))
                    x += r(w * 0.7, w * 1.2)
                }
            }
            for _ in 0..<7 { // hanging vines
                let vx = r(0, s.width)
                var vine = Path(); vine.move(to: CGPoint(x: vx, y: 0))
                vine.addQuadCurve(to: CGPoint(x: vx + r(-10, 10), y: r(40, 110)), control: CGPoint(x: vx + r(-20, 20), y: 30))
                c.stroke(vine, with: .color(t.ground.opacity(0.45)), lineWidth: 1.2)
            }
            for _ in 0..<12 { // big leaves in front
                var leaf = c
                leaf.translateBy(x: r(0, s.width), y: s.height - r(0, s.height * 0.12))
                leaf.rotate(by: .degrees(Double(r(-60, 60))))
                leaf.fill(Path(ellipseIn: CGRect(x: -6, y: -26, width: 12, height: 28)), with: .color(t.ground.opacity(0.7)))
            }
            if movers { for _ in 0..<8 { glowCircle(CGPoint(x: r(0, s.width), y: r(s.height * 0.3, s.height * 0.8)), 4, t.glow, 0.7) } }

        case .snow:
            // Tundra: icy peaks, a snowfield, and its animals standing on it. Snow falls in AmbientScene.
            var peaks = Path(); peaks.move(to: CGPoint(x: 0, y: s.height * 0.75))
            for (px, py) in [(0.12, 0.5), (0.25, 0.68), (0.42, 0.42), (0.6, 0.66), (0.78, 0.48), (0.92, 0.62), (1.0, 0.56)] {
                peaks.addLine(to: CGPoint(x: s.width * px, y: s.height * py))
            }
            peaks.addLine(to: CGPoint(x: s.width, y: s.height)); peaks.addLine(to: CGPoint(x: 0, y: s.height)); peaks.closeSubpath()
            c.fill(peaks, with: .color(t.groundShade.opacity(night ? 0.55 : 0.4)))
            for (px, py) in [(0.12, 0.5), (0.42, 0.42), (0.78, 0.48)] { // snow caps
                var cap = Path()
                cap.move(to: CGPoint(x: s.width * px, y: s.height * py))
                cap.addLine(to: CGPoint(x: s.width * px - 14, y: s.height * py + 16)); cap.addLine(to: CGPoint(x: s.width * px + 14, y: s.height * py + 16)); cap.closeSubpath()
                c.fill(cap, with: .color(Color.white.opacity(night ? 0.5 : 0.85)))
            }
            var field = Path(); field.move(to: CGPoint(x: 0, y: s.height))
            field.addLine(to: CGPoint(x: 0, y: s.height * 0.78))
            field.addCurve(to: CGPoint(x: s.width, y: s.height * 0.76), control1: CGPoint(x: s.width * 0.3, y: s.height * 0.72), control2: CGPoint(x: s.width * 0.7, y: s.height * 0.84))
            field.addLine(to: CGPoint(x: s.width, y: s.height)); field.closeSubpath()
            c.fill(field, with: .color(night ? Color.white.opacity(0.16) : Color.white.opacity(0.8)))
            let ground = s.height * 0.84
            Sprite.draw(Sprite.polarBear, in: &c, anchor: CGPoint(x: s.width * 0.18, y: ground), px: 2)
            Sprite.draw(Sprite.penguin, in: &c, anchor: CGPoint(x: s.width * 0.4, y: ground + 2), px: 2)
            Sprite.draw(Sprite.penguin, in: &c, anchor: CGPoint(x: s.width * 0.44, y: ground + 3), px: 2)
            Sprite.draw(Sprite.snowFox, in: &c, anchor: CGPoint(x: s.width * 0.66, y: ground), px: 2)
            Sprite.draw(Sprite.snowOwl, in: &c, anchor: CGPoint(x: s.width * 0.9, y: ground - 1), px: 2)
            if movers { for _ in 0..<40 { dot(r(0, s.width), r(0, s.height), r(1.5, 3.5), Color.white.opacity(night ? 0.7 : 0.9)) } }

        case .ember:
            // A campsite: pines against the sky, tents and a campfire whose glow lights the ground.
            if night { stars(40, maxY: 0.45, .white) }
            var x: CGFloat = -10
            while x < s.width + 20 {
                let h = r(50, 95), w = h * 0.45, base = s.height * 0.74
                var pine = Path()
                pine.move(to: CGPoint(x: x - w / 2, y: base)); pine.addLine(to: CGPoint(x: x, y: base - h)); pine.addLine(to: CGPoint(x: x + w / 2, y: base)); pine.closeSubpath()
                c.fill(pine, with: .color(t.groundShade.opacity(night ? 0.7 : 0.45)))
                x += r(w * 0.6, w * 1.2)
            }
            c.fill(Path(CGRect(x: 0, y: s.height * 0.74, width: s.width, height: s.height * 0.26)), with: .color(t.groundShade.opacity(0.75)))
            let fire = CGPoint(x: s.width * 0.55, y: s.height * 0.84)
            glowCircle(fire, min(s.width, s.height) * 0.45, t.glow, night ? 0.32 : 0.2)
            for (tx, tw) in [(0.22, 70.0), (0.82, 56.0)] {
                var tent = Path()
                let bx = s.width * tx, by = s.height * 0.82
                tent.move(to: CGPoint(x: bx - tw / 2, y: by)); tent.addLine(to: CGPoint(x: bx, y: by - tw * 0.7)); tent.addLine(to: CGPoint(x: bx + tw / 2, y: by)); tent.closeSubpath()
                c.fill(tent, with: .color(t.accentStrong.opacity(0.75)))
                var door = Path(); door.move(to: CGPoint(x: bx - 8, y: by)); door.addLine(to: CGPoint(x: bx, y: by - tw * 0.4)); door.addLine(to: CGPoint(x: bx + 8, y: by)); door.closeSubpath()
                c.fill(door, with: .color(t.sceneTop.opacity(0.8)))
            }
            for a in [-0.4, 0.4] { // logs
                var log = c
                log.translateBy(x: fire.x, y: fire.y + 2)
                log.rotate(by: .radians(a))
                log.fill(Path(roundedRect: CGRect(x: -16, y: -3, width: 32, height: 6), cornerRadius: 3), with: .color(Color(hex: 0x6B4A3A)))
            }
            if movers { dot(fire.x, fire.y - 10, 14, t.tagLater) }

        case .cyberpunk:
            // A hazy skyline of towers with lit windows and neon signs; rain and flying cars move in AmbientScene.
            c.fill(Path(CGRect(x: 0, y: s.height * 0.35, width: s.width, height: s.height * 0.65)),
                   with: .linearGradient(Gradient(colors: [t.glow.opacity(0), t.glow.opacity(night ? 0.18 : 0.12)]),
                                         startPoint: CGPoint(x: 0, y: s.height * 0.35), endPoint: CGPoint(x: 0, y: s.height)))
            for layer in 0..<2 {
                var x: CGFloat = -10
                while x < s.width + 10 {
                    let w = r(18, 46), h = r(s.height * (0.3 + CGFloat(layer) * 0.1), s.height * (0.75 - CGFloat(layer) * 0.1))
                    let tower = CGRect(x: x, y: s.height - h, width: w, height: h)
                    c.fill(Path(tower), with: .color(t.sceneTop.opacity(layer == 0 ? 0.55 : 0.92)))
                    if layer == 1 {
                        var wy = tower.minY + 6
                        while wy < s.height - 6 {
                            var wx = tower.minX + 3
                            while wx < tower.maxX - 3 {
                                if r(0, 1) < 0.28 { c.fill(Path(CGRect(x: wx, y: wy, width: 2, height: 2)), with: .color([t.tagLater, t.accentLight, t.tagLearning][Int(r(0, 2.99))].opacity(0.75))) }
                                wx += 5
                            }
                            wy += 6
                        }
                        if r(0, 1) < 0.35 { // a neon sign down the side
                            let sign = CGRect(x: tower.maxX - 4, y: tower.minY + r(10, 30), width: 3, height: r(18, 40))
                            glowCircle(CGPoint(x: sign.midX, y: sign.midY), 18, t.accent, 0.35)
                            c.fill(Path(sign), with: .color([t.accent, t.tagHigh, t.tagLearning][Int(r(0, 2.99))]))
                        }
                    }
                    x += w + r(2, 8)
                }
            }
        }
    }
}
