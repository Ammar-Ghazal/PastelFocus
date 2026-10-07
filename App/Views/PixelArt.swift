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

    static func forItem(_ item: GardenItem) -> [String] {
        switch item.kind {
        case .wilted: return wilted
        case .richSoil: return soil
        case .sleepingCat: return cat
        case .ripple: return ripple
        case .plant:
            if item.size == .sprout { return sprout }
            switch item.species ?? .grassTuft {
            case .crystalPine: return crystalPine
            case .lanternFlower: return lanternFlower
            case .fern: return fern
            case .blossomTree: return blossomTree
            case .grassTuft: return grassTuft
            }
        }
    }

    static func forCategory(_ c: String?) -> [String] {
        switch Species.forCategory(c) {
        case .crystalPine: return crystalPine
        case .lanternFlower: return lanternFlower
        case .fern: return fern
        case .blossomTree: return blossomTree
        case .grassTuft: return grassTuft
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

/// One week's island: pixel plants on a grid, landmarks, fireflies drifting at 8 fps.
struct IslandView: View {
    @Environment(\.theme) private var theme
    let island: Island?
    let landmarks: [Landmark]
    var cell: CGFloat = 26
    var animate = true

    /// Only fireflies and the waterfall move; without them nothing is redrawn.
    private var moving: Bool { animate && ((island?.fireflies ?? 0) > 0 || landmarks.contains(.waterfall)) }
    @Environment(\.snapshotMode) private var snapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The island is drawn once; only the small overlay animates (keeps CPU low).
        Canvas { ctx, size in
            var c = ctx
            drawStatic(&c, size: size)
        }
        .overlay {
            if moving && !snapshot && !reduceMotion {
                // Core Animation runs in the render server, so the app itself stays near 0% CPU.
                AmbientLayer(fireflies: min(island?.fireflies ?? 0, 40), waterfall: landmarks.contains(.waterfall),
                             cell: cell, columns: Garden.columns, rows: Garden.rows)
            } else {
                Canvas { ctx, size in
                    var c = ctx
                    drawMoving(&c, size: size, t: 0)
                }
            }
        }
        .frame(width: cell * CGFloat(Garden.columns) + 24, height: cell * CGFloat(Garden.rows) + 34)
    }

    private var geometry: (w: CGFloat, h: CGFloat, px: CGFloat) {
        (cell * CGFloat(Garden.columns), cell * CGFloat(Garden.rows), max(2, (cell / 8).rounded(.down)))
    }

    private func drawStatic(_ ctx: inout GraphicsContext, size: CGSize) {
        let (w, h, px) = geometry
        let ox = (size.width - w) / 2, oy: CGFloat = 16
        // Island ground: layered rounded blobs.
        let ground = Path(roundedRect: CGRect(x: ox - 8, y: oy + 6, width: w + 16, height: h + 4), cornerRadius: 22)
        ctx.fill(ground, with: .color(theme.groundShade))
        ctx.fill(Path(roundedRect: CGRect(x: ox - 4, y: oy + 2, width: w + 8, height: h), cornerRadius: 20), with: .color(theme.ground))
        ctx.fill(Path(roundedRect: CGRect(x: ox - 8, y: oy + h + 2, width: w + 16, height: 10), cornerRadius: 5), with: .color(theme.sceneTop))

        func centre(_ x: Int, _ y: Int) -> CGPoint { CGPoint(x: ox + (CGFloat(x) + 0.5) * cell, y: oy + (CGFloat(y) + 1) * cell) }

        for lm in landmarks {
            switch lm {
            case .path:
                for (x, y) in lm.cells { ctx.fill(Path(ellipseIn: CGRect(x: centre(x, y).x - cell * 0.35, y: centre(x, y).y - cell * 0.4, width: cell * 0.7, height: cell * 0.3)), with: .color(Color(hex: 0xF8DFA1, opacity: 0.55))) }
            case .pond:
                let a = centre(9, 4), b = centre(10, 5)
                ctx.fill(Path(ellipseIn: CGRect(x: a.x - cell * 0.5, y: a.y - cell * 0.8, width: b.x - a.x + cell, height: b.y - a.y + cell * 0.7)), with: .color(Color(hex: 0x5FB3C4, opacity: 0.85)))
            case .stoneLantern: Sprite.draw(Sprite.stoneLantern, in: &ctx, anchor: centre(5, 1), px: px)
            case .redBridge: Sprite.draw(Sprite.bridge, in: &ctx, anchor: centre(8, 4), px: px)
            case .smallHouse: Sprite.draw(Sprite.house, in: &ctx, anchor: CGPoint(x: centre(2, 0).x + cell / 2, y: centre(2, 0).y), px: px)
            case .waterfall:
                let top = centre(11, 0)
                ctx.fill(Path(CGRect(x: top.x - px * 2, y: top.y - cell, width: px * 4, height: cell * 2)), with: .color(Color(hex: 0x5FB3C4, opacity: 0.6)))
            }
        }

        for item in (island?.items ?? []).sorted(by: { $0.y < $1.y }) {
            let scale: CGFloat
            switch item.size {
            case .large?: scale = 1.5
            case .medium?: scale = 1.2
            default: scale = 1
            }
            Sprite.draw(Sprite.forItem(item), in: &ctx, anchor: centre(item.x, item.y), px: (px * scale).rounded(),
                        tint: item.variant == .golden ? Color(hex: 0xF8DFA1) : nil, glow: item.variant != .normal)
        }

    }

    private func drawMoving(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let (w, h, px) = geometry
        let ox = (size.width - w) / 2, oy: CGFloat = 16
        if landmarks.contains(.waterfall) {
            let top = CGPoint(x: ox + 11.5 * cell, y: oy + cell)
            for i in 0..<4 {
                let yy = top.y - cell + CGFloat((Int(t * 8) + i * 3) % 12) * cell / 6
                ctx.fill(Path(CGRect(x: top.x - px, y: yy, width: px * 2, height: px * 3)), with: .color(Color(hex: 0x8DE4E6, opacity: 0.8)))
            }
        }
        // Fireflies: one per task finished this week.
        let flies = island?.fireflies ?? 0
        for i in 0..<min(flies, 40) {
            var rng = SeededRandom(seed: UInt64(i + 1) &* 7919)
            let bx = CGFloat.random(in: 0...1, using: &rng), by = CGFloat.random(in: 0...1, using: &rng)
            let phase = Double.random(in: 0...6.28, using: &rng)
            let x = ox + bx * w + CGFloat(sin(t * 0.7 + phase)) * 6, y = oy + by * h * 0.8 + CGFloat(cos(t * 0.5 + phase)) * 4
            let a = 0.45 + 0.4 * sin(t * 2 + phase)
            ctx.fill(Path(CGRect(x: x, y: y, width: 2, height: 2)), with: .color(Color(hex: 0xF8DFA1, opacity: a)))
        }
    }
}

/// Monthly postcard rendered to PNG at month end.
struct PostcardView: View {
    @Environment(\.theme) private var theme
    let month: String
    let islands: [Island]
    let garden: Garden

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("✦ \(month)").font(theme.titleFont(22)).foregroundStyle(theme.accent)
            HStack(spacing: 10) {
                ForEach(islands, id: \.week) { island in
                    VStack(spacing: 4) {
                        IslandView(island: island, landmarks: garden.landmarks, cell: 14, animate: false)
                        Text(island.week).font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.textSecondary)
                    }
                }
            }
            Text("\(garden.goodDays) good days · \(islands.flatMap(\.items).filter { $0.kind == .plant }.count) plants")
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
    let cell: CGFloat
    let columns: Int
    let rows: Int

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        DispatchQueue.main.async { build(in: v) }
    }

    private func build(in v: NSView) {
        guard let root = v.layer else { return }
        root.sublayers?.forEach { $0.removeFromSuperlayer() }
        let w = cell * CGFloat(columns), h = cell * CGFloat(rows)
        let ox = (v.bounds.width - w) / 2
        // NSView layers are flipped relative to the Canvas: y grows upwards.
        let top = v.bounds.height - 16
        for i in 0..<fireflies {
            var rng = SeededRandom(seed: UInt64(i + 1) &* 7919)
            let x = ox + CGFloat.random(in: 0...1, using: &rng) * w
            let y = top - CGFloat.random(in: 0...1, using: &rng) * h * 0.8
            let fly = CALayer()
            fly.frame = CGRect(x: x, y: y, width: 2, height: 2)
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
            let px = max(2, (cell / 8).rounded(.down))
            let x = ox + 11.5 * cell
            for i in 0..<4 {
                let drop = CALayer()
                drop.frame = CGRect(x: x - px, y: top, width: px * 2, height: px * 3)
                drop.backgroundColor = NSColor(red: 0.553, green: 0.894, blue: 0.902, alpha: 0.8).cgColor
                let fall = CABasicAnimation(keyPath: "position.y")
                fall.fromValue = top
                fall.toValue = top - cell * 2
                fall.duration = 1.5
                fall.timeOffset = Double(i) * 0.375
                fall.repeatCount = .infinity
                drop.add(fall, forKey: "fall")
                root.addSublayer(drop)
            }
        }
    }
}
