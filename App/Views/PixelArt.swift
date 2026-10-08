import PastelFocusCore
import SwiftUI

/// Tiny pixel sprites drawn in code (no image assets needed). Each string row is one pixel row;
/// letters map to palette colours, "." is transparent.
enum Sprite {
    static let palette: [Character: UInt32] = [
        "C": 0x8DE4E6, "c": 0x5FB3C4, "L": 0xFFD2E6, "P": 0xF6A6CF, "p": 0xEC779F, "M": 0x91E0BF, "m": 0x5BAE8C,
        "T": 0x8A6A5A, "t": 0x5E4A44, "Y": 0xF8DFA1, "y": 0xD9B86A, "V": 0xB9B7FF, "v": 0x8C89E6, "W": 0xF5EDF6,
        "G": 0x6F8F7A, "B": 0x3B3048, "R": 0xE05A6A, "r": 0xA8404E, "S": 0x7A7E95, "s": 0x575B70, "K": 0x252338,
        "O": 0xFF8291, "D": 0x2E2638,
    ]

    static let sprout = ["........", "........", "...M....", "..mM.M..", "...MMm..", "....M...", "...TT...", "........"]
    static let crystalPine = ["....C...", "...CcC..", "...cCc..", "..CcCcC.", "..cCcCc.", ".CcCcCcC", "....T...", "....T..."]
    static let lanternFlower = ["...PP...", "..PLLP..", "..PLYP..", "...PP...", "....M...", "..M.M.M.", "...MMM..", "....M..."]
    static let fern = [".M.....M", "..M...M.", ".mM.M.Mm", "..MmMmM.", "...MMM..", "....M...", "...Y.Y..", "..YyYyY."]
    static let blossomTree = ["..PLPP..", ".PLPPLP.", "PPLPPPLP", ".PPLPPP.", "..PPLP..", "....T...", "....T...", "...TtT.."]
    static let grassTuft = ["........", "........", "........", "..M..M..", "M.mM.Mm.", ".MmMMmM.", "mMMmMMMm", "........"]
    static let wilted = ["........", "........", "..y.....", "...y....", "...yT...", "....T...", "...tt...", "........"]
    static let soil = ["........", "........", "........", "........", "........", "..tDtD..", ".DtDtDt.", "..DtDt.."]
    static let cat = ["........", "........", "W....W..", "WW..WW..", "WWWWWWW.", "WKWWKWWW", "WWWWWWWW", ".WWWWWW."]
    static let ripple = ["........", "........", "........", "..CCCC..", ".C....C.", "..CCCC..", "........", "........"]
    static let stoneLantern = ["...SS...", "..SSSS..", "...YY...", "..SYYS..", "...SS...", "...SS...", "..SSSS..", ".ssssss."]
    static let house = ["....rr........", "...rRRr.......", "..rRRRRr......", ".rRRRRRRr.....", "rRRRRRRRRr....", ".TYTTTTYT.....", ".TYTTTTYT.....", ".TTTDDTTT....."]
    static let bridge = ["........", "........", ".RRRRRR.", "R.R..R.R", "R......R", "........", "........", "........"]
    static let catMascot = ["P......P", "PP....PP", "PLLLLLLP", "LKLLLLKL", "LLLppLLL", ".LLLLLL.", "..L..L..", "........"]

    static let mushroom = ["........", "..pPPp..", ".pPWPPp.", "pPPPPWPp", "...WW...", "...WW...", "..WWWW..", "........"]
    static let cactus = ["...M....", "...M..M.", "M..M..M.", "M..MMMM.", "MMMM....", "...M....", "..tTTt..", "..tttt.."]
    static let sunflower = ["..Y.Y...", ".YYyYY..", "YYyByYY.", ".YYyYY..", "..YMY...", "...M.M..", "..MM....", "...M...."]
    static let berryBush = ["..mMMm..", ".mMRMMm.", "mMMMRMMm", "mRMMMMRm", ".mMMRMm.", "..mMMm..", "...TT...", "........"]
    static let crystalCluster = ["....V...", "..V.Vv..", "..VvVv.V", ".VvVvVvV", ".vVvVvV.", "..vVvV..", "..SSSS..", ".ssssss."]

    /// A garden item's sprite: plants come from their tag's slot (via `art`), the rest are fixed.
    static func forItem(_ item: GardenItem, art: PlantArt) -> [String] {
        switch item.kind {
        case .wilted: return wilted
        case .richSoil: return soil
        case .sleepingCat: return cat
        case .ripple: return ripple
        case .plant: return item.size == .sprout ? sprout : art.sprite(forTag: item.tag)
        }
    }

    /// Draws `rows` with its bottom-centre at `anchor`, `px` points per pixel.
    static func draw(_ rows: [String], in ctx: inout GraphicsContext, anchor: CGPoint, px: CGFloat, tint: Color? = nil, glow: Bool = false) {
        let w = CGFloat(rows.map(\.count).max() ?? 0) * px, h = CGFloat(rows.count) * px
        let origin = CGPoint(x: (anchor.x - w / 2).rounded(), y: (anchor.y - h).rounded())
        if glow {
            let r = max(w, h) * 0.75
            let c = CGPoint(x: anchor.x, y: anchor.y - h / 2)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                     with: .radialGradient(Gradient(colors: [Color(hex: 0xF8DFA1, opacity: 0.35), Color(hex: 0xF8DFA1, opacity: 0)]),
                                           center: c, startRadius: 0, endRadius: r))
        }
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() where ch != "." {
                guard let hex = palette[ch] else { continue }
                let rect = CGRect(x: origin.x + CGFloat(x) * px, y: origin.y + CGFloat(y) * px, width: px, height: px)
                ctx.fill(Path(rect), with: .color(tint ?? Color(hex: hex)))
            }
        }
    }
}

/// A sprite as a view, e.g. the progress mascot or category icons.
struct SpriteView: View {
    let rows: [String]
    var px: CGFloat = 2
    var body: some View {
        Canvas { ctx, size in
            var c = ctx
            Sprite.draw(rows, in: &c, anchor: CGPoint(x: size.width / 2, y: size.height), px: px)
        }
        .frame(width: CGFloat(rows.map(\.count).max() ?? 8) * px, height: CGFloat(rows.count) * px)
    }
}

/// Where everything sits on an isometric plot drawn into `size`. Tiles shrink as the plot grows,
/// which is the "zoom out" (shared by the drawing and the animated layer so they line up).
struct IsoGeometry {
    let side: Int
    let size: CGSize

    /// Tile width; a tile is half as tall as it is wide.
    let tile: CGFloat
    /// Depth of the soil block under the grass.
    let depth: CGFloat
    /// Top (back) corner of the grass.
    let apex: CGPoint

    init(side: Int, size: CGSize) {
        self.side = side
        self.size = size
        let n = CGFloat(side)
        // Height needed per tile width: the diamond (n/2), the soil (0.6) and room for the back row's plants (1.1).
        tile = max(1, min(size.width * 0.94 / n, (size.height - 4) / (n / 2 + 1.7)))
        depth = max(4, tile * 0.6)
        let total = tile * 1.1 + n * tile / 2 + depth
        apex = CGPoint(x: size.width / 2, y: (size.height - total) / 2 + tile * 1.1)
    }

    var halfWidth: CGFloat { CGFloat(side) * tile / 2 }
    var left: CGPoint { CGPoint(x: apex.x - halfWidth, y: apex.y + halfWidth / 2) }
    var right: CGPoint { CGPoint(x: apex.x + halfWidth, y: apex.y + halfWidth / 2) }
    var front: CGPoint { CGPoint(x: apex.x, y: apex.y + halfWidth) }

    /// Centre of a tile's top face.
    func centre(_ x: Int, _ y: Int) -> CGPoint { point(CGFloat(x) + 0.5, CGFloat(y) + 0.5) }

    /// Any point on the grass, in tile units.
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: apex.x + (x - y) * tile / 2, y: apex.y + (x + y) * tile / 4)
    }

    func diamond(_ x: Int, _ y: Int) -> Path {
        let fx = CGFloat(x), fy = CGFloat(y)
        var p = Path()
        p.move(to: point(fx, fy)); p.addLine(to: point(fx + 1, fy)); p.addLine(to: point(fx + 1, fy + 1)); p.addLine(to: point(fx, fy + 1))
        p.closeSubpath()
        return p
    }

    /// Pixel size for an 8-pixel-wide sprite filling most of a tile.
    var px: CGFloat { tile * 0.8 / 8 }
}

/// A period's garden as a Forest-style isometric block of land. Drawn once; only fireflies and the
/// waterfall move, as Core Animation layers.
struct IsoPlotView: View {
    @Environment(\.theme) private var theme
    @Environment(\.plantArt) private var plantArt
    @Environment(\.snapshotMode) private var snapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let plot: GardenPlot
    var animate = true

    private var moving: Bool { animate && !snapshot && !reduceMotion && (plot.fireflies > 0 || plot.landmarks.contains(.waterfall)) }

    var body: some View {
        Canvas { ctx, size in
            var c = ctx
            draw(&c, IsoGeometry(side: plot.side, size: size))
        }
        .overlay {
            if moving {
                AmbientLayer(fireflies: min(plot.fireflies, 40), waterfall: plot.landmarks.contains(.waterfall), side: plot.side)
            }
        }
    }

    private func draw(_ ctx: inout GraphicsContext, _ g: IsoGeometry) {
        let down = CGSize(width: 0, height: g.depth)
        // Soft shadow, then the soil block's two visible faces, then the grass.
        let shadowH = g.halfWidth * 0.22
        ctx.fill(Path(ellipseIn: CGRect(x: g.left.x + g.halfWidth * 0.1, y: g.front.y + g.depth - shadowH * 0.55, width: g.halfWidth * 1.8, height: shadowH)),
                 with: .color(.black.opacity(0.16)))
        for (a, b, shade) in [(g.left, g.front, 0.0), (g.front, g.right, 0.22)] {
            var face = Path()
            face.move(to: a); face.addLine(to: b); face.addLine(to: b + down); face.addLine(to: a + down); face.closeSubpath()
            ctx.fill(face, with: .color(theme.groundShade))
            ctx.fill(face, with: .color(.black.opacity(shade)))
            var lip = Path() // grass hanging over the soil edge
            lip.move(to: a); lip.addLine(to: b); lip.addLine(to: b + CGSize(width: 0, height: g.depth * 0.22)); lip.addLine(to: a + CGSize(width: 0, height: g.depth * 0.22))
            ctx.fill(lip, with: .color(theme.ground))
            ctx.fill(lip, with: .color(.black.opacity(shade * 0.6)))
        }
        for x in 0..<g.side { for y in 0..<g.side {
            ctx.fill(g.diamond(x, y), with: .color(theme.ground))
            if (x + y) % 2 == 0 { ctx.fill(g.diamond(x, y), with: .color(.white.opacity(0.05))) }
        } }

        drawLandmarks(&ctx, g)

        // Back to front, so nearer plants overlap farther ones.
        for item in plot.items.sorted(by: { ($0.x + $0.y, $0.x) < ($1.x + $1.y, $1.x) }) {
            let scale: CGFloat = item.size == .large ? 1.35 : item.size == .medium ? 1.15 : 1
            let c = g.centre(item.x, item.y)
            Sprite.draw(Sprite.forItem(item, art: plantArt), in: &ctx, anchor: CGPoint(x: c.x, y: c.y + g.tile * 0.12), px: g.px * scale,
                        tint: item.variant == .golden ? Color(hex: 0xF8DFA1) : nil, glow: item.variant != .normal)
        }

        if !moving { // still frame: fireflies as dots
            for p in AmbientLayer.fireflyPoints(min(plot.fireflies, 40), g) {
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1, y: p.y - 1, width: 2, height: 2)), with: .color(Color(hex: 0xF8DFA1, opacity: 0.75)))
            }
        }
    }

    private func drawLandmarks(_ ctx: inout GraphicsContext, _ g: IsoGeometry) {
        for lm in plot.landmarks {
            let tiles = lm.tiles(side: g.side)
            switch lm {
            case .path:
                for t in tiles { ctx.fill(g.diamond(t.x, t.y), with: .color(Color(hex: 0xF8DFA1, opacity: 0.45))) }
            case .pond:
                for t in tiles { ctx.fill(g.diamond(t.x, t.y), with: .color(Color(hex: 0x5FB3C4, opacity: 0.9))) }
            case .stoneLantern:
                Sprite.draw(Sprite.stoneLantern, in: &ctx, anchor: g.centre(tiles[0].x, tiles[0].y), px: g.px)
            case .redBridge:
                Sprite.draw(Sprite.bridge, in: &ctx, anchor: g.centre(tiles[0].x, tiles[0].y), px: g.px)
            case .smallHouse:
                let a = g.centre(tiles[0].x, tiles[0].y), b = g.centre(tiles[1].x, tiles[1].y)
                Sprite.draw(Sprite.house, in: &ctx, anchor: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 + g.tile * 0.15), px: g.px)
            case .waterfall:
                let r = g.right
                ctx.fill(Path(CGRect(x: r.x - g.px * 3, y: r.y - g.tile * 0.2, width: g.px * 2.5, height: g.depth + g.tile * 0.4)),
                         with: .color(Color(hex: 0x5FB3C4, opacity: 0.7)))
            }
        }
    }
}

private func + (p: CGPoint, s: CGSize) -> CGPoint { CGPoint(x: p.x + s.width, y: p.y + s.height) }

/// Monthly postcard rendered to PNG.
struct PostcardView: View {
    @Environment(\.theme) private var theme
    let title: String
    let plot: GardenPlot
    let garden: Garden

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(theme.titleFont(22)).foregroundStyle(theme.accent)
            IsoPlotView(plot: plot, animate: false).frame(width: 520, height: 360)
            Text("\(plot.items.filter { $0.kind == .plant }.count) plants · \(garden.goodDays) good days")
                .font(.system(size: 12)).foregroundStyle(theme.textSecondary)
        }
        .padding(24)
        .background(SceneArt(theme: theme))
    }
}

/// Fireflies and waterfall drops as CALayers with repeating animations (no per-frame app work).
struct AmbientLayer: NSViewRepresentable {
    let fireflies: Int
    let waterfall: Bool
    let side: Int

    /// Where each firefly hovers, a little above the grass (seeded, so they don't jump between redraws).
    static func fireflyPoints(_ count: Int, _ g: IsoGeometry) -> [CGPoint] {
        (0..<count).map { i in
            var rng = SeededRandom(seed: UInt64(i + 1) &* 7919)
            let n = CGFloat(g.side)
            let p = g.point(CGFloat.random(in: 0.5...(n - 0.5), using: &rng), CGFloat.random(in: 0.5...(n - 0.5), using: &rng))
            return CGPoint(x: p.x, y: p.y - g.tile * CGFloat.random(in: 0.4...1.2, using: &rng))
        }
    }

    func makeNSView(context: Context) -> AmbientView {
        let v = AmbientView()
        v.wantsLayer = true
        v.build = build
        return v
    }

    func updateNSView(_ v: AmbientView, context: Context) {
        v.build = build
        v.inputs = "\(fireflies)|\(waterfall)|\(side)"
    }

    /// Rebuilds the layers only when the inputs or size change. SwiftUI updates the view often, and
    /// rebuilding every time restarted the animations (fireflies jumped back to their start).
    final class AmbientView: NSView {
        var build: ((NSView) -> Void)?
        var inputs = "" { didSet { rebuildIfNeeded() } }
        private var built = ""

        override func layout() {
            super.layout()
            rebuildIfNeeded()
        }

        private func rebuildIfNeeded() {
            let key = "\(inputs)|\(bounds.size)"
            guard key != built, bounds.width > 0, bounds.height > 0 else { return }
            built = key
            build?(self)
        }
    }

    private func build(in v: NSView) {
        guard let root = v.layer else { return }
        root.sublayers?.forEach { $0.removeFromSuperlayer() }
        let g = IsoGeometry(side: side, size: v.bounds.size)
        let h = v.bounds.height // layers have y growing upwards; the Canvas grows downwards
        for (i, p) in Self.fireflyPoints(fireflies, g).enumerated() {
            var rng = SeededRandom(seed: UInt64(i + 101) &* 104_729)
            let fly = CALayer()
            fly.frame = CGRect(x: p.x - 1, y: h - p.y - 1, width: 2, height: 2)
            fly.cornerRadius = 1
            fly.backgroundColor = NSColor(red: 0.973, green: 0.875, blue: 0.631, alpha: 1).cgColor
            let blink = CABasicAnimation(keyPath: "opacity")
            blink.fromValue = 0.1; blink.toValue = 0.9
            blink.duration = Double.random(in: 1.4...2.8, using: &rng)
            blink.autoreverses = true; blink.repeatCount = .infinity
            let drift = CABasicAnimation(keyPath: "position")
            drift.byValue = NSValue(point: CGPoint(x: CGFloat.random(in: -6...6, using: &rng), y: CGFloat.random(in: -4...4, using: &rng)))
            drift.duration = Double.random(in: 3...5, using: &rng)
            drift.autoreverses = true; drift.repeatCount = .infinity
            fly.add(blink, forKey: "blink")
            fly.add(drift, forKey: "drift")
            root.addSublayer(fly)
        }
        if waterfall {
            let top = h - (g.right.y - g.tile * 0.2), fallBy = g.depth + g.tile * 0.4
            for i in 0..<4 {
                let drop = CALayer()
                drop.frame = CGRect(x: g.right.x - g.px * 2.5, y: top, width: g.px * 1.5, height: g.px * 3)
                drop.backgroundColor = NSColor(red: 0.553, green: 0.894, blue: 0.902, alpha: 0.85).cgColor
                let fall = CABasicAnimation(keyPath: "position.y")
                fall.fromValue = top
                fall.toValue = top - fallBy
                fall.duration = 1.2
                fall.timeOffset = Double(i) * 0.3
                fall.repeatCount = .infinity
                drop.add(fall, forKey: "fall")
                root.addSublayer(drop)
            }
        }
    }
}
