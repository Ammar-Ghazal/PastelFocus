import PastelFocusCore
import SwiftUI

/// How the Focus panel draws time (its ⋯ menu). Every style shows the same value: the share of the
/// session still to go, or while idle, the chosen length out of the 120-minute maximum.
enum TimerStyle: String, CaseIterable, Identifiable {
    case ring, clock, hourglass, water

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ring: return "Ring"
        case .clock: return "Clock"
        case .hourglass: return "Hourglass"
        case .water: return "Water drip"
        }
    }

    var symbol: String {
        switch self {
        case .ring: return "circle.dashed"
        case .clock: return "clock"
        case .hourglass: return "hourglass"
        case .water: return "drop"
        }
    }

    /// Ring and clock are set by dragging around the face; the others by dragging up and down.
    var isCircular: Bool { self == .ring || self == .clock }
}

/// A clock face with the time left as a filled wedge from 12 o'clock, like a kitchen timer.
struct ClockFace: View {
    @Environment(\.theme) var theme
    let fill: Double
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(theme.track.opacity(0.45))
            Sector(fraction: fill).fill(theme.accent.opacity(0.85))
            ForEach(0..<12) { i in
                Capsule().fill(theme.textTertiary.opacity(i % 3 == 0 ? 0.9 : 0.5))
                    .frame(width: i % 3 == 0 ? 2 : 1.2, height: i % 3 == 0 ? 7 : 4)
                    .offset(y: -size / 2 + 6)
                    .rotationEffect(.degrees(Double(i) * 30))
            }
            Capsule().fill(theme.textPrimary).frame(width: 2.5, height: size / 2 - 12)
                .offset(y: -(size / 2 - 12) / 2)
                .rotationEffect(.degrees(fill * 360))
            Circle().fill(theme.textPrimary).frame(width: 7, height: 7)
        }
        .frame(width: size, height: size)
    }
}

/// A pie slice from 12 o'clock, clockwise.
struct Sector: Shape {
    var fraction: Double
    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        guard fraction > 0 else { return p }
        let c = CGPoint(x: r.midX, y: r.midY)
        p.move(to: c)
        p.addArc(center: c, radius: min(r.width, r.height) / 2, startAngle: .degrees(-90),
                 endAngle: .degrees(-90 + 360 * min(1, fraction)), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// An hourglass: the top bulb holds the time left, the bottom what has passed. A thin stream runs
/// through the neck while the timer runs.
struct Hourglass: View {
    @Environment(\.theme) var theme
    let fill: Double
    let size: CGFloat
    let flowing: Bool

    var body: some View {
        let w = size * 0.58, h = size * 0.86
        ZStack {
            Canvas { ctx, s in draw(ctx, CGSize(width: s.width, height: s.height)) }
                .frame(width: w, height: h)
            if flowing {
                TimelineView(.periodic(from: .now, by: 0.12)) { tl in
                    let phase = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.48) / 0.48
                    Capsule().fill(theme.accent)
                        .frame(width: 1.6, height: h * 0.3)
                        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: phase * 0.5),
                                                     .init(color: .black, location: 0.5 + phase * 0.5), .init(color: .clear, location: 1)],
                                             startPoint: .top, endPoint: .bottom))
                        .offset(y: h * 0.15)
                }
            }
        }
        .frame(width: size, height: size)
    }

    private func draw(_ ctx: GraphicsContext, _ s: CGSize) {
        let mid = s.height / 2, neck: CGFloat = 3, half = s.height / 2 - 4
        let glass = Path { p in
            p.move(to: CGPoint(x: 0, y: 2)); p.addLine(to: CGPoint(x: s.width, y: 2))
            p.addLine(to: CGPoint(x: s.width / 2 + neck, y: mid)); p.addLine(to: CGPoint(x: s.width, y: s.height - 2))
            p.addLine(to: CGPoint(x: 0, y: s.height - 2)); p.addLine(to: CGPoint(x: s.width / 2 - neck, y: mid))
            p.closeSubpath()
        }
        ctx.fill(glass, with: .color(theme.track.opacity(0.45)))
        // Sand in a cone: the amount grows with the square of its height, so heights use square roots.
        let top = max(0, min(1, fill)), bottom = 1 - top
        let topH = half * sqrt(top)
        if topH > 0.5 {
            let k = topH / half // width of the sand's surface, relative to the bulb's top
            ctx.fill(Path { p in
                p.move(to: CGPoint(x: s.width / 2 - neck, y: mid)); p.addLine(to: CGPoint(x: s.width / 2 + neck, y: mid))
                p.addLine(to: CGPoint(x: s.width / 2 + neck + (s.width / 2 - neck) * k, y: mid - topH))
                p.addLine(to: CGPoint(x: s.width / 2 - neck - (s.width / 2 - neck) * k, y: mid - topH))
                p.closeSubpath()
            }, with: .color(theme.accent))
        }
        let botH = half * (1 - sqrt(max(0, 1 - bottom)))
        if botH > 0.5 {
            let k = 1 - botH / half
            ctx.fill(Path { p in
                p.move(to: CGPoint(x: 0, y: s.height - 2)); p.addLine(to: CGPoint(x: s.width, y: s.height - 2))
                p.addLine(to: CGPoint(x: s.width / 2 + neck + (s.width / 2 - neck) * k, y: s.height - 2 - botH))
                p.addLine(to: CGPoint(x: s.width / 2 - neck - (s.width / 2 - neck) * k, y: s.height - 2 - botH))
                p.closeSubpath()
            }, with: .color(theme.accent.opacity(0.75)))
        }
        ctx.stroke(glass, with: .color(theme.textTertiary.opacity(0.8)), lineWidth: 1.5)
        for y in [CGFloat(1), s.height - 1] {
            ctx.stroke(Path { p in p.move(to: CGPoint(x: -3, y: y)); p.addLine(to: CGPoint(x: s.width + 3, y: y)) },
                       with: .color(theme.textSecondary), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }
}

/// A tank that drains drop by drop: the water level is the time left.
struct WaterDrip: View {
    @Environment(\.theme) var theme
    let fill: Double
    let size: CGFloat
    let dripping: Bool

    var body: some View {
        let w = size * 0.62, h = size * 0.68
        ZStack(alignment: .top) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 12).fill(theme.track.opacity(0.45))
                WaveRect(level: max(0, min(1, fill))).fill(theme.accent.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                RoundedRectangle(cornerRadius: 12).strokeBorder(theme.textTertiary.opacity(0.8), lineWidth: 1.5)
            }
            .frame(width: w, height: h)
            // Spout under the tank.
            Capsule().fill(theme.textTertiary).frame(width: 6, height: 7).offset(y: h - 1)
            if dripping {
                TimelineView(.periodic(from: .now, by: 1.0 / 20)) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
                    Drop().fill(theme.accent)
                        .frame(width: 6, height: 9)
                        .offset(y: h + 6 + t * t * (size - h - 12))
                        .opacity(1 - t * 0.8)
                }
            }
        }
        .frame(width: size, height: size, alignment: .top)
    }
}

/// A filled rectangle up to `level` (0–1) with a gentle wave on top.
struct WaveRect: Shape {
    var level: Double
    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in r: CGRect) -> Path {
        let y = r.maxY - r.height * level
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: y))
        p.addCurve(to: CGPoint(x: r.maxX, y: y), control1: CGPoint(x: r.minX + r.width * 0.33, y: y - 3),
                   control2: CGPoint(x: r.minX + r.width * 0.66, y: y + 3))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct Drop: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY - r.width / 2), control: CGPoint(x: r.maxX, y: r.midY))
        p.addArc(center: CGPoint(x: r.midX, y: r.maxY - r.width / 2), radius: r.width / 2, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY), control: CGPoint(x: r.minX, y: r.midY))
        return p
    }
}
