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
        case .pastelRetro:
            for _ in 0..<14 {
                let x = r(0, s.width), y = r(0, s.height), p: CGFloat = 2
                c.fill(Path(CGRect(x: x, y: y, width: p, height: p)), with: .color(t.particle.opacity(0.35)))
                c.fill(Path(CGRect(x: x - p, y: y, width: p * 3, height: p / 2 + 0.5)), with: .color(t.particle.opacity(0.15)))
            }

        case .deepSpace:
            stars(90, maxY: 1, night ? .white : t.textTertiary)
            let sun = CGPoint(x: s.width * 0.88, y: s.height * 0.12)
            glowCircle(sun, min(s.width, s.height) * 0.35, t.glow, 0.35)
            dot(sun.x, sun.y, 14, t.glow)
            for (i, radius) in [0.18, 0.30, 0.44].enumerated() {
                let rr = min(s.width, s.height) * radius
                c.stroke(Path(ellipseIn: CGRect(x: sun.x - rr, y: sun.y - rr * 0.6, width: rr * 2, height: rr * 1.2)),
                         with: .color(t.textTertiary.opacity(0.18)), lineWidth: 0.7)
                if movers {
                    let a = Double(i) * 2.1 + 2.4
                    dot(sun.x + rr * cos(a), sun.y + rr * 0.6 * sin(a), [5, 8, 6][i], i == 1 ? t.ground : t.accentLight)
                }
            }

        case .enchantedForest:
            c.fill(Path(CGRect(x: 0, y: s.height * 0.62, width: s.width, height: s.height * 0.2)),
                   with: .linearGradient(Gradient(colors: [Color.white.opacity(0), Color.white.opacity(night ? 0.06 : 0.25), Color.white.opacity(0)]),
                                         startPoint: CGPoint(x: 0, y: s.height * 0.62), endPoint: CGPoint(x: 0, y: s.height * 0.82)))
            var x: CGFloat = -10
            while x < s.width + 20 {
                let h = r(s.height * 0.16, s.height * 0.32), w = h * 0.42, base = s.height + 4
                var tree = Path()
                for tier in 0..<3 {
                    let ty = base - h * CGFloat(tier) * 0.28
                    tree.move(to: CGPoint(x: x - w / 2 + CGFloat(tier) * w * 0.12, y: ty))
                    tree.addLine(to: CGPoint(x: x, y: ty - h * 0.5))
                    tree.addLine(to: CGPoint(x: x + w / 2 - CGFloat(tier) * w * 0.12, y: ty))
                }
                c.fill(tree, with: .color(t.groundShade.opacity(night ? 0.55 : 0.35)))
                x += r(w * 0.7, w * 1.4)
            }
            if movers { for _ in 0..<10 { glowCircle(CGPoint(x: r(0, s.width), y: r(s.height * 0.3, s.height * 0.85)), 5, t.glow, 0.8) } }

        case .oceanDepths:
            for i in 0..<5 {
                let x0 = s.width * (0.1 + CGFloat(i) * 0.22)
                var ray = Path()
                ray.move(to: CGPoint(x: x0, y: 0)); ray.addLine(to: CGPoint(x: x0 + 30, y: 0))
                ray.addLine(to: CGPoint(x: x0 + 90, y: s.height)); ray.addLine(to: CGPoint(x: x0 + 40, y: s.height)); ray.closeSubpath()
                c.fill(ray, with: .linearGradient(Gradient(colors: [t.glow.opacity(night ? 0.10 : 0.18), t.glow.opacity(0)]),
                                                  startPoint: .zero, endPoint: CGPoint(x: 0, y: s.height)))
            }
            var bed = Path()
            bed.move(to: CGPoint(x: 0, y: s.height))
            stride(from: 0, through: s.width, by: 40).forEach { bx in bed.addQuadCurve(to: CGPoint(x: bx + 40, y: s.height - r(4, 18)), control: CGPoint(x: bx + 20, y: s.height - r(10, 26))) }
            bed.addLine(to: CGPoint(x: s.width, y: s.height)); bed.closeSubpath()
            c.fill(bed, with: .color(t.groundShade.opacity(0.4)))
            if movers { for _ in 0..<12 { c.stroke(Path(ellipseIn: CGRect(x: r(0, s.width), y: r(0, s.height), width: 6, height: 6)), with: .color(t.particle.opacity(0.4)), lineWidth: 1) } }

        case .synthwave:
            stars(40, maxY: 0.55, night ? .white : t.textTertiary)
            let horizon = s.height * 0.68
            let sun = CGPoint(x: s.width * 0.5, y: horizon - 2)
            let radius = min(s.width, s.height) * 0.28
            glowCircle(sun, radius * 1.8, t.glow, 0.25)
            var disc = Path(ellipseIn: CGRect(x: sun.x - radius, y: sun.y - radius, width: radius * 2, height: radius * 2))
            disc = disc.intersection(Path(CGRect(x: 0, y: 0, width: s.width, height: horizon)))
            c.fill(disc, with: .linearGradient(Gradient(colors: [t.tagLater, t.accentStrong]), startPoint: CGPoint(x: 0, y: sun.y - radius), endPoint: CGPoint(x: 0, y: horizon)))
            for i in 0..<5 { c.fill(Path(CGRect(x: sun.x - radius, y: horizon - CGFloat(i) * 9 - 6, width: radius * 2, height: CGFloat(i) * 0.7 + 1.5)), with: .color(t.sceneBottom)) }
            c.fill(Path(CGRect(x: 0, y: horizon, width: s.width, height: s.height - horizon)), with: .color(t.sceneTop.opacity(0.6)))
            let grid = t.accent.opacity(0.35)
            for i in 0...14 {
                let x = s.width * CGFloat(i) / 14
                var l = Path(); l.move(to: CGPoint(x: s.width / 2 + (x - s.width / 2) * 0.15, y: horizon)); l.addLine(to: CGPoint(x: s.width / 2 + (x - s.width / 2) * 2.2, y: s.height))
                c.stroke(l, with: .color(grid), lineWidth: 0.8)
            }
            for i in 1...7 {
                let y = horizon + (s.height - horizon) * pow(CGFloat(i) / 7, 1.8)
                c.stroke(Path(CGRect(x: 0, y: y, width: s.width, height: 0.01)), with: .color(grid), lineWidth: 0.8)
            }

        case .zenPaper:
            for _ in 0..<700 { dot(r(0, s.width), r(0, s.height), r(0.4, 1.1), t.textTertiary.opacity(0.06)) }
            let center = CGPoint(x: s.width * 0.8, y: s.height * 0.78), radius = min(s.width, s.height) * 0.18
            for i in 0..<26 {
                let a0 = Angle.degrees(Double(i) * 12 - 70), a1 = Angle.degrees(Double(i + 1) * 12 - 70)
                var arc = Path(); arc.addArc(center: center, radius: radius, startAngle: a0, endAngle: a1, clockwise: false)
                c.stroke(arc, with: .color(t.textPrimary.opacity(0.10)), style: StrokeStyle(lineWidth: 2 + 7 * sin(Double(i) / 26 * .pi), lineCap: .round))
            }

        case .cozyAutumn:
            glowCircle(CGPoint(x: s.width * 0.1, y: s.height * 0.1), min(s.width, s.height) * 0.6, t.glow, night ? 0.18 : 0.25)
            var hill = Path()
            hill.move(to: CGPoint(x: 0, y: s.height))
            hill.addCurve(to: CGPoint(x: s.width, y: s.height * 0.9), control1: CGPoint(x: s.width * 0.3, y: s.height * 0.78), control2: CGPoint(x: s.width * 0.7, y: s.height * 0.98))
            hill.addLine(to: CGPoint(x: s.width, y: s.height)); hill.closeSubpath()
            c.fill(hill, with: .color(t.groundShade.opacity(0.45)))
            if movers {
                for _ in 0..<9 {
                    var leaf = c
                    leaf.translateBy(x: r(0, s.width), y: r(0, s.height))
                    leaf.rotate(by: .degrees(Double(r(0, 360))))
                    leaf.fill(Path(ellipseIn: CGRect(x: -5, y: -2.5, width: 10, height: 5)), with: .color([t.accent, t.tagLater, t.tagHigh][Int(r(0, 2.99))].opacity(0.6)))
                }
            }

        case .aurora:
            stars(70, maxY: 0.7, night ? .white : t.textTertiary)
            if movers {
                for i in 0..<3 {
                    var band = Path()
                    let y0 = s.height * (0.18 + CGFloat(i) * 0.12)
                    band.move(to: CGPoint(x: -20, y: y0))
                    band.addCurve(to: CGPoint(x: s.width + 20, y: y0 + 10), control1: CGPoint(x: s.width * 0.3, y: y0 - 40), control2: CGPoint(x: s.width * 0.7, y: y0 + 50))
                    band.addLine(to: CGPoint(x: s.width + 20, y: y0 + 70)); band.addCurve(to: CGPoint(x: -20, y: y0 + 60), control1: CGPoint(x: s.width * 0.7, y: y0 + 110), control2: CGPoint(x: s.width * 0.3, y: y0 + 20))
                    c.fill(band, with: .linearGradient(Gradient(colors: [[t.accent, t.tagHealth, t.tagFocus][i].opacity(night ? 0.28 : 0.22), .clear]),
                                                       startPoint: CGPoint(x: 0, y: y0), endPoint: CGPoint(x: 0, y: y0 + 80)))
                }
            }
            var ridge = Path(); ridge.move(to: CGPoint(x: 0, y: s.height))
            ridge.addLine(to: CGPoint(x: 0, y: s.height * 0.86)); ridge.addLine(to: CGPoint(x: s.width * 0.25, y: s.height * 0.78))
            ridge.addLine(to: CGPoint(x: s.width * 0.45, y: s.height * 0.88)); ridge.addLine(to: CGPoint(x: s.width * 0.7, y: s.height * 0.74))
            ridge.addLine(to: CGPoint(x: s.width, y: s.height * 0.86)); ridge.addLine(to: CGPoint(x: s.width, y: s.height)); ridge.closeSubpath()
            c.fill(ridge, with: .color(t.groundShade.opacity(0.6)))

        case .desertDusk:
            let sun = CGPoint(x: s.width * 0.25, y: s.height * 0.62)
            glowCircle(sun, min(s.width, s.height) * 0.5, t.glow, 0.3)
            dot(sun.x, sun.y, min(s.width, s.height) * 0.16, t.tagLater.opacity(0.85))
            for (i, col) in [t.ground.opacity(0.55), t.groundShade.opacity(0.75)].enumerated() {
                var dune = Path()
                let y = s.height * (0.7 + CGFloat(i) * 0.1)
                dune.move(to: CGPoint(x: 0, y: s.height)); dune.addLine(to: CGPoint(x: 0, y: y))
                dune.addCurve(to: CGPoint(x: s.width, y: y - 10), control1: CGPoint(x: s.width * 0.35, y: y - 40), control2: CGPoint(x: s.width * 0.6, y: y + 30))
                dune.addLine(to: CGPoint(x: s.width, y: s.height)); dune.closeSubpath()
                c.fill(dune, with: .color(col))
            }
            if night { stars(30, maxY: 0.4, .white) }

        case .sakura:
            var branch = Path()
            branch.move(to: CGPoint(x: s.width + 10, y: s.height * 0.05))
            branch.addCurve(to: CGPoint(x: s.width * 0.55, y: s.height * 0.22), control1: CGPoint(x: s.width * 0.85, y: s.height * 0.02), control2: CGPoint(x: s.width * 0.7, y: s.height * 0.25))
            branch.move(to: CGPoint(x: s.width * 0.78, y: s.height * 0.1))
            branch.addQuadCurve(to: CGPoint(x: s.width * 0.7, y: s.height * 0.32), control: CGPoint(x: s.width * 0.8, y: s.height * 0.25))
            c.stroke(branch, with: .color(t.groundShade.opacity(night ? 0.8 : 0.6)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            for _ in 0..<26 { dot(r(s.width * 0.55, s.width), r(0, s.height * 0.32), r(4, 8), [t.accentLight, t.accent][Int(r(0, 1.99))].opacity(0.75)) }
            if movers { for _ in 0..<10 { dot(r(0, s.width), r(s.height * 0.3, s.height), 4, t.accentLight.opacity(0.6)) } }

        case .terminal:
            var y: CGFloat = 0
            while y < s.height { c.fill(Path(CGRect(x: 0, y: y, width: s.width, height: 1)), with: .color(t.accent.opacity(0.05))); y += 3 }
            glowCircle(CGPoint(x: s.width / 2, y: s.height / 2), max(s.width, s.height) * 0.7, t.accent, 0.06)
            let prompt = Text(">_").font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundColor(t.accent.opacity(0.35))
            c.draw(prompt, at: CGPoint(x: 18, y: s.height - 14))

        case .winter:
            var hills = Path(); hills.move(to: CGPoint(x: 0, y: s.height))
            hills.addCurve(to: CGPoint(x: s.width, y: s.height * 0.86), control1: CGPoint(x: s.width * 0.3, y: s.height * 0.72), control2: CGPoint(x: s.width * 0.6, y: s.height * 0.95))
            hills.addLine(to: CGPoint(x: s.width, y: s.height)); hills.closeSubpath()
            c.fill(hills, with: .color(night ? Color.white.opacity(0.10) : Color.white.opacity(0.7)))
            for i in 0..<4 {
                let x = s.width * (0.12 + CGFloat(i) * 0.08), base = s.height * 0.93
                var pine = Path(); pine.move(to: CGPoint(x: x - 9, y: base)); pine.addLine(to: CGPoint(x: x, y: base - 26)); pine.addLine(to: CGPoint(x: x + 9, y: base)); pine.closeSubpath()
                c.fill(pine, with: .color(t.groundShade.opacity(0.7)))
            }
            if movers { for _ in 0..<40 { dot(r(0, s.width), r(0, s.height), r(1.5, 3.5), Color.white.opacity(night ? 0.7 : 0.9)) } }
        }
    }
}
