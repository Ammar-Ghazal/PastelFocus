import AppKit
import PastelFocusCore
import SwiftUI

/// Ambient motion for a theme, built from Core Animation layers and particle emitters.
/// It all runs in the window server's render loop, so the app does no per-frame work.
struct AmbientScene: NSViewRepresentable {
    let theme: Theme

    func makeNSView(context: Context) -> AmbientView { AmbientView() }

    func updateNSView(_ v: AmbientView, context: Context) {
        v.configure(scene: theme.scene, palette: theme.palette)
    }
}

final class AmbientView: NSView {
    private var key = ""
    private var scene: SceneKind = .cherryBlossom
    private var palette: Palette?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil } // never steals clicks

    func configure(scene: SceneKind, palette: Palette) {
        self.scene = scene
        self.palette = palette
        rebuildIfNeeded()
    }

    override func layout() {
        super.layout()
        rebuildIfNeeded()
    }

    private func rebuildIfNeeded() {
        guard let palette, bounds.width > 0 else { return }
        let newKey = "\(scene.rawValue)|\(palette.id)|\(Int(bounds.width))x\(Int(bounds.height))"
        guard newKey != key, let root = layer else { return }
        key = newKey
        root.sublayers?.forEach { $0.removeFromSuperlayer() }
        build(scene, palette, in: root, size: bounds.size)
    }

    // MARK: Builders

    private func build(_ scene: SceneKind, _ p: Palette, in root: CALayer, size s: CGSize) {
        var rng = SeededRandom(seed: stableHash(p.id + "motion"))
        func r(_ a: CGFloat, _ b: CGFloat) -> CGFloat { CGFloat.random(in: a...b, using: &rng) }
        let white = RGBA(r: 1, g: 1, b: 1)

        switch scene {
        case .space:
            twinkles(24, color: p.isDark ? white : p.textTertiary, in: root, s, &rng)
            planets(p, in: root, s)
            flyBy(Sprites.pixel(Sprite.rocket, px: 2), from: CGPoint(x: -20, y: s.height * 0.35), to: CGPoint(x: s.width + 20, y: s.height * 0.62),
                  travel: 16, every: 47, offset: 6, rotation: -.pi / 2 + 0.25, in: root)
            flyBy(Sprites.pixel(Sprite.ufo, px: 2), from: CGPoint(x: s.width + 20, y: s.height * 0.78), to: CGPoint(x: -20, y: s.height * 0.7),
                  travel: 22, every: 89, offset: 40, in: root)
            shootingStar(in: root, s, every: 23)
        case .cherryBlossom:
            root.addSublayer(emitter(image: Sprites.petal, colors: [p.accentLight, p.accent, p.accentStrong], alpha: 0.85, at: CGPoint(x: s.width * 0.75, y: s.height + 6),
                                     width: s.width * 0.6, rate: 1.1, life: Float(s.height / 15), velocity: 15, longitude: -.pi / 2 - 0.35, spin: 1.5, scale: 0.55))
            root.addSublayer(emitter(image: Sprites.leaf, colors: [p.tagHealth, p.ground], alpha: 0.75, at: CGPoint(x: s.width * 0.75, y: s.height + 6),
                                     width: s.width * 0.5, rate: 0.25, life: Float(s.height / 13), velocity: 13, longitude: -.pi / 2 - 0.3, spin: 1.1, scale: 0.45))
        case .rainforest:
            rainforest(p, in: root, s, &rng)
        case .snow:
            root.addSublayer(emitter(image: Sprites.dot, color: white, alpha: p.isDark ? 0.8 : 0.95, at: CGPoint(x: s.width / 2, y: s.height + 6),
                                     width: s.width, rate: 6, life: Float(s.height / 18), velocity: 18, longitude: -.pi / 2, spin: 0, scale: 0.35))
            root.addSublayer(emitter(image: Sprites.dot, color: white, alpha: 0.6, at: CGPoint(x: s.width / 2, y: s.height + 6),
                                     width: s.width, rate: 0.8, life: Float(s.height / 11), velocity: 11, longitude: -.pi / 2 + 0.2, spin: 0, scale: 0.7))
        case .ember:
            let fire = CGPoint(x: s.width * 0.55, y: s.height * 0.16 + 4) // SceneArt's campfire (layers count y up)
            flame(p, at: fire, in: root)
            root.addSublayer(emitter(image: Sprites.dot, colors: [p.tagLater, p.glow, p.tagHigh], alpha: 0.9, at: fire, width: 14,
                                     rate: 4, life: 3.5, velocity: 34, longitude: .pi / 2, spin: 0, scale: 0.22))
            drifters(9, color: p.tagHealth, size: 3, glow: true, area: CGRect(x: 0, y: s.height * 0.2, width: s.width, height: s.height * 0.5), in: root, &rng)
        case .cyberpunk:
            root.addSublayer(emitter(image: Sprites.streak, color: p.isDark ? white : p.textTertiary, alpha: 0.35, at: CGPoint(x: s.width / 2 + 20, y: s.height + 6),
                                     width: s.width * 1.2, rate: 14, life: Float(s.height / 120), velocity: 120, longitude: -.pi / 2 - 0.12, spin: 0, scale: 0.6))
            for (k, (y, travel, every)) in [(0.62, 9.0, 17.0), (0.74, 13.0, 29.0), (0.52, 7.0, 37.0)].enumerated() {
                let car = Sprites.carLights(color: k == 1 ? p.tagHigh : p.tagLearning)
                let ltr = k != 1
                flyBy(car, from: CGPoint(x: ltr ? -20 : s.width + 20, y: s.height * y), to: CGPoint(x: ltr ? s.width + 20 : -20, y: s.height * (y + 0.03)),
                      travel: travel, every: every, offset: Double(k) * 5, in: root)
            }
            neonSign(p, at: CGRect(x: s.width * 0.12, y: s.height * 0.42, width: 54, height: 14), in: root)
        }
    }

    // MARK: Scene pieces

    /// `image` crosses from `from` to `to` in `travel` seconds, once every `every` seconds.
    private func flyBy(_ image: CGImage, from: CGPoint, to: CGPoint, travel: Double, every: Double, offset: Double,
                       rotation: CGFloat = 0, in root: CALayer) {
        let l = CALayer()
        l.contents = image
        l.contentsGravity = .center
        l.magnificationFilter = .nearest
        l.bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        l.position = from
        l.transform = CATransform3DMakeRotation(rotation, 0, 0, 1)
        l.opacity = 0
        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = NSValue(point: from); move.toValue = NSValue(point: to)
        move.duration = travel
        let show = CAKeyframeAnimation(keyPath: "opacity")
        show.values = [0, 1, 1, 0]; show.keyTimes = [0, 0.05, 0.95, 1]; show.duration = travel
        let group = CAAnimationGroup()
        group.animations = [move, show]
        group.duration = every
        group.repeatCount = .infinity
        group.timeOffset = offset
        l.add(group, forKey: "flyBy")
        root.addSublayer(l)
    }

    private func shootingStar(in root: CALayer, _ s: CGSize, every: Double) {
        let g = CAGradientLayer()
        g.bounds = CGRect(x: 0, y: 0, width: 60, height: 1.5)
        g.colors = [CGColor(gray: 1, alpha: 0), CGColor(gray: 1, alpha: 0.9)]
        g.startPoint = CGPoint(x: 0, y: 0.5); g.endPoint = CGPoint(x: 1, y: 0.5)
        g.transform = CATransform3DMakeRotation(-0.5, 0, 0, 1)
        g.opacity = 0
        let from = CGPoint(x: s.width * 0.3, y: s.height * 0.95), to = CGPoint(x: s.width * 0.6, y: s.height * 0.78)
        g.position = from
        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = NSValue(point: from); move.toValue = NSValue(point: to); move.duration = 0.9
        let show = CAKeyframeAnimation(keyPath: "opacity")
        show.values = [0, 1, 0]; show.keyTimes = [0, 0.3, 1]; show.duration = 0.9
        let group = CAAnimationGroup()
        group.animations = [move, show]; group.duration = every; group.repeatCount = .infinity; group.timeOffset = 4
        g.add(group, forKey: "shoot")
        root.addSublayer(g)
    }

    /// Rainforest weather: a light level (day, dusk or night) picked at random each time the scene
    /// is built, and rain that comes and goes in random bursts.
    private func rainforest(_ p: Palette, in root: CALayer, _ s: CGSize, _ rng: inout SeededRandom) {
        var chance = SystemRandomNumberGenerator() // not seeded: the weather changes from launch to launch
        let light = ["day", "dusk", "night"].randomElement(using: &chance)!
        let tint = CAGradientLayer()
        tint.frame = CGRect(origin: .zero, size: s)
        switch light {
        case "day":
            tint.colors = [cg(p.glow.withAlpha(0)), cg(p.glow.withAlpha(0.16))] // sunlight from the top
        case "dusk":
            tint.colors = [cg(RGBA(r: 0.35, g: 0.15, b: 0.35, a: 0.18)), cg(RGBA(r: 1, g: 0.55, b: 0.2, a: 0.16))]
        default:
            tint.colors = [cg(RGBA(r: 0, g: 0.02, b: 0.08, a: 0.42)), cg(RGBA(r: 0, g: 0.02, b: 0.08, a: 0.3))]
        }
        root.addSublayer(tint)
        if light == "night" {
            drifters(10, color: p.glow, size: 3, glow: true, area: CGRect(x: 0, y: 0, width: s.width, height: s.height * 0.6), in: root, &rng)
        }
        let rain = emitter(image: Sprites.streak, color: RGBA(r: 0.85, g: 0.92, b: 1), alpha: 0.4, at: CGPoint(x: s.width / 2, y: s.height + 6),
                           width: s.width * 1.1, rate: 18, life: Float(s.height / 140), velocity: 140, longitude: -.pi / 2 - 0.05, spin: 0, scale: 0.6)
        // Raining for about a third of a 4–7 minute cycle, starting at a random point in it.
        let cycle = Double.random(in: 240...420, using: &chance)
        let start = Double.random(in: 0.05...0.55, using: &chance), length = Double.random(in: 0.25...0.4, using: &chance)
        let bursts = CAKeyframeAnimation(keyPath: "birthRate")
        bursts.values = [0, 0, 1, 1, 0, 0]
        bursts.keyTimes = [0, start, start + 0.03, start + length, start + length + 0.03, 1].map { NSNumber(value: min(1, $0)) }
        bursts.duration = cycle
        bursts.repeatCount = .infinity
        bursts.timeOffset = Double.random(in: 0...cycle, using: &chance)
        rain.birthRate = 0
        rain.add(bursts, forKey: "bursts")
        root.addSublayer(rain)
    }

    /// A flickering flame over the campfire.
    private func flame(_ p: Palette, at fire: CGPoint, in root: CALayer) {
        for (k, (w, col)) in [(26.0, p.tagHigh), (16.0, p.tagLater)].enumerated() {
            let f = CAShapeLayer()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 0))
            path.addQuadCurve(to: CGPoint(x: w / 2, y: w * 1.5), control: CGPoint(x: -w * 0.1, y: w))
            path.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w * 1.1, y: w))
            path.closeSubpath()
            f.path = path
            f.fillColor = cg(col.withAlpha(0.85))
            f.bounds = CGRect(x: 0, y: 0, width: w, height: w * 1.5)
            f.anchorPoint = CGPoint(x: 0.5, y: 0)
            f.position = CGPoint(x: fire.x, y: fire.y - 4)
            f.shadowColor = cg(col); f.shadowRadius = 8; f.shadowOpacity = 0.8; f.shadowOffset = .zero
            let flicker = CAKeyframeAnimation(keyPath: "transform.scale.y")
            flicker.values = [1, 1.15, 0.92, 1.08, 0.96, 1]
            flicker.duration = 0.9 + Double(k) * 0.3
            flicker.repeatCount = .infinity
            f.add(flicker, forKey: "flicker")
            root.addSublayer(f)
        }
    }

    /// A neon sign that flickers now and then.
    private func neonSign(_ p: Palette, at frame: CGRect, in root: CALayer) {
        let sign = CALayer()
        sign.frame = frame
        sign.cornerRadius = 4
        sign.borderWidth = 2
        sign.borderColor = cg(p.accent)
        sign.shadowColor = cg(p.accent); sign.shadowRadius = 6; sign.shadowOpacity = 1; sign.shadowOffset = .zero
        let flicker = CAKeyframeAnimation(keyPath: "opacity")
        flicker.values = [1, 1, 0.2, 1, 0.3, 1, 1]
        flicker.keyTimes = [0, 0.8, 0.82, 0.84, 0.86, 0.88, 1]
        flicker.duration = 7
        flicker.repeatCount = .infinity
        sign.add(flicker, forKey: "flicker")
        root.addSublayer(sign)
    }

    private func twinkles(_ n: Int, color: RGBA, in root: CALayer, _ s: CGSize, _ rng: inout SeededRandom, maxY: CGFloat = 1) {
        for _ in 0..<n {
            let d = CGFloat.random(in: 1.4...2.6, using: &rng)
            let star = CALayer()
            star.frame = CGRect(x: CGFloat.random(in: 0...s.width, using: &rng), y: s.height - CGFloat.random(in: 0...(s.height * maxY), using: &rng), width: d, height: d)
            star.cornerRadius = d / 2
            star.backgroundColor = cg(color)
            star.add(pulse(from: 0.15, to: 0.95, duration: Double.random(in: 1.6...3.6, using: &rng), offset: Double.random(in: 0...3, using: &rng)), forKey: "twinkle")
            root.addSublayer(star)
        }
    }

    private func drifters(_ n: Int, color: RGBA, size d: CGFloat, glow: Bool, area: CGRect, in root: CALayer, _ rng: inout SeededRandom) {
        for _ in 0..<n {
            let l = CALayer()
            l.frame = CGRect(x: area.minX + CGFloat.random(in: 0...area.width, using: &rng), y: area.minY + CGFloat.random(in: 0...area.height, using: &rng), width: d, height: d)
            l.cornerRadius = d / 2
            l.backgroundColor = cg(color)
            if glow { l.shadowColor = cg(color); l.shadowRadius = 4; l.shadowOpacity = 0.9; l.shadowOffset = .zero }
            l.add(pulse(from: 0.1, to: 1, duration: Double.random(in: 1.5...3, using: &rng), offset: Double.random(in: 0...3, using: &rng)), forKey: "blink")
            let drift = CABasicAnimation(keyPath: "position")
            drift.byValue = NSValue(point: CGPoint(x: CGFloat.random(in: -14...14, using: &rng), y: CGFloat.random(in: -10...10, using: &rng)))
            drift.duration = Double.random(in: 4...7, using: &rng)
            drift.autoreverses = true; drift.repeatCount = .infinity
            drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            l.add(drift, forKey: "drift")
            root.addSublayer(l)
        }
    }

    /// Three planets on slow orbits around a glowing sun (periods 70–220 s).
    private func planets(_ p: Palette, in root: CALayer, _ s: CGSize) {
        let sun = CGPoint(x: s.width * 0.86, y: s.height * 0.86) // SceneArt's sun (layers count y up)
        for (i, (radius, size, period)) in [(0.18, 5.0, 70.0), (0.30, 8.0, 140.0), (0.44, 6.0, 220.0)].enumerated() {
            let rr = min(s.width, s.height) * radius
            let orbit = CALayer()
            orbit.frame = CGRect(x: sun.x - rr, y: sun.y - rr, width: rr * 2, height: rr * 2)
            orbit.transform = CATransform3DMakeScale(1, 0.6, 1) // tilt the orbit into an ellipse
            let planet = CALayer()
            planet.frame = CGRect(x: rr * 2 - size / 2, y: rr - size / 2, width: size, height: size)
            planet.cornerRadius = size / 2
            planet.backgroundColor = cg(i == 1 ? p.ground : p.accentLight)
            orbit.addSublayer(planet)
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = Double(i) * 2.1
            spin.toValue = Double(i) * 2.1 + 2 * .pi
            spin.duration = period
            spin.repeatCount = .infinity
            orbit.add(spin, forKey: "orbit")
            root.addSublayer(orbit)
        }
    }

    private func ribbons(_ p: Palette, in root: CALayer, _ s: CGSize) {
        for (i, col) in [p.accent, p.tagHealth, p.tagFocus].enumerated() {
            let g = CAGradientLayer()
            g.frame = CGRect(x: -s.width * 0.3, y: s.height * (0.55 - CGFloat(i) * 0.1), width: s.width * 1.6, height: s.height * 0.22)
            g.colors = [cg(col.withAlpha(0)), cg(col.withAlpha(p.isDark ? 0.30 : 0.22)), cg(col.withAlpha(0))]
            g.startPoint = CGPoint(x: 0.5, y: 0); g.endPoint = CGPoint(x: 0.5, y: 1)
            g.transform = CATransform3DMakeRotation(CGFloat(i) * 0.08 - 0.08, 0, 0, 1)
            let sway = CABasicAnimation(keyPath: "position.x")
            sway.byValue = s.width * 0.18
            sway.duration = 9 + Double(i) * 3
            sway.autoreverses = true; sway.repeatCount = .infinity
            sway.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            g.add(sway, forKey: "sway")
            g.add(pulse(from: 0.45, to: 1, duration: 6 + Double(i) * 2, offset: Double(i)), forKey: "glow")
            root.addSublayer(g)
        }
    }

    private func cursor(_ p: Palette, in root: CALayer, _ s: CGSize) {
        let c = CALayer()
        c.frame = CGRect(x: 36, y: 8, width: 8, height: 13)
        c.backgroundColor = cg(p.accent.withAlpha(0.45))
        let blink = CAKeyframeAnimation(keyPath: "opacity")
        blink.values = [1, 1, 0, 0]
        blink.keyTimes = [0, 0.5, 0.5, 1]
        blink.duration = 1.1
        blink.repeatCount = .infinity
        c.add(blink, forKey: "blink")
        root.addSublayer(c)
    }

    private func pulse(from: Double, to: Double, duration: Double, offset: Double) -> CABasicAnimation {
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = from; a.toValue = to
        a.duration = duration; a.autoreverses = true; a.repeatCount = .infinity
        a.timeOffset = offset
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return a
    }

    private func emitter(image: CGImage, color: RGBA? = nil, colors: [RGBA]? = nil, alpha: Float, at pos: CGPoint,
                         width: CGFloat, height: CGFloat = 1, rate: Float, life: Float, velocity: CGFloat,
                         longitude: CGFloat, spin: CGFloat, scale: CGFloat) -> CAEmitterLayer {
        let e = CAEmitterLayer()
        e.emitterPosition = pos
        e.emitterShape = .rectangle
        e.emitterSize = CGSize(width: width, height: height)
        e.renderMode = .unordered
        let tints = colors ?? [color ?? RGBA(r: 1, g: 1, b: 1)]
        e.emitterCells = tints.map { tint in
            let c = CAEmitterCell()
            c.contents = image
            c.color = cg(tint.withAlpha(Double(alpha)))
            c.birthRate = rate / Float(tints.count)
            c.lifetime = life
            c.velocity = velocity
            c.velocityRange = velocity * 0.35
            c.emissionLongitude = longitude
            c.emissionRange = 0.25
            c.spin = spin
            c.spinRange = spin
            c.scale = scale
            c.scaleRange = scale * 0.4
            c.alphaSpeed = -alpha / life * 0.6
            return c
        }
        // Start part-way through so the panel isn't empty at launch.
        e.beginTime = CACurrentMediaTime() - Double(life) * 0.6
        return e
    }

    private func cg(_ c: RGBA) -> CGColor { CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a) }
}

/// Tiny white particle images, tinted per cell.
enum Sprites {
    static let dot = make(10) { ctx, r in ctx.fillEllipse(in: r) }
    static let ring = make(12) { ctx, r in ctx.setLineWidth(1.5); ctx.strokeEllipse(in: r.insetBy(dx: 1, dy: 1)) }
    static let petal = make(14) { ctx, r in ctx.fillEllipse(in: CGRect(x: r.minX, y: r.minY + r.height * 0.25, width: r.width, height: r.height * 0.5)) }
    static let streak = make(12) { ctx, r in ctx.fill(CGRect(x: r.midX - 0.5, y: 0, width: 1, height: r.height)) }
    static let leaf = make(16) { ctx, r in
        let p = CGMutablePath()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.midY), control: CGPoint(x: r.midX, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.midY), control: CGPoint(x: r.midX, y: r.minY))
        ctx.addPath(p); ctx.fillPath()
    }

    /// A pixel sprite (see `Sprite`) as an image, `px` pixels per sprite pixel.
    static func pixel(_ rows: [String], px: Int) -> CGImage {
        let w = (rows.map(\.count).max() ?? 1) * px, h = rows.count * px
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() where ch != "." {
                guard let hex = Sprite.palette[ch] else { continue }
                ctx.setFillColor(CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1))
                ctx.fill(CGRect(x: x * px, y: (rows.count - 1 - y) * px, width: px, height: px))
            }
        }
        return ctx.makeImage()!
    }

    /// Two headlights and a tail light: a flying car at night.
    static func carLights(color: RGBA) -> CGImage {
        let ctx = CGContext(data: nil, width: 22, height: 6, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0.15, green: 0.15, blue: 0.2, alpha: 0.9)); ctx.fill(CGRect(x: 2, y: 1, width: 18, height: 4))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0.97, blue: 0.85, alpha: 1)); ctx.fill(CGRect(x: 18, y: 2, width: 4, height: 2))
        ctx.setFillColor(CGColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: 1)); ctx.fill(CGRect(x: 0, y: 2, width: 3, height: 2))
        return ctx.makeImage()!
    }

    private static func make(_ size: Int, _ draw: (CGContext, CGRect) -> Void) -> CGImage {
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
        draw(ctx, CGRect(x: 0, y: 0, width: size, height: size))
        return ctx.makeImage()!
    }
}
