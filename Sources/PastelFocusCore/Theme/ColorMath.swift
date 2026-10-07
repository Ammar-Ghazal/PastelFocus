import Foundation

/// Platform-neutral sRGB colour (0...1 components). Used by the core and the app.
public struct RGBA: Codable, Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public init(hex: UInt32, alpha: Double = 1) {
        self.init(r: Double((hex >> 16) & 0xff) / 255, g: Double((hex >> 8) & 0xff) / 255,
                  b: Double(hex & 0xff) / 255, a: alpha)
    }

    public func withAlpha(_ a: Double) -> RGBA { RGBA(r: r, g: g, b: b, a: a) }

    public var hexString: String {
        String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    public var isInGamut: Bool { [r, g, b, a].allSatisfy { $0 >= -1e-9 && $0 <= 1 + 1e-9 } }

    /// WCAG relative luminance.
    public var luminance: Double {
        0.2126 * Self.toLinear(r) + 0.7152 * Self.toLinear(g) + 0.0722 * Self.toLinear(b)
    }

    /// WCAG contrast ratio (1...21), ignoring alpha.
    public func contrast(with other: RGBA) -> Double {
        let (l1, l2) = (luminance, other.luminance)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    /// Straight-alpha "source over" composite onto an opaque background.
    public func over(_ bg: RGBA) -> RGBA {
        RGBA(r: r * a + bg.r * (1 - a), g: g * a + bg.g * (1 - a), b: b * a + bg.b * (1 - a), a: 1)
    }

    static func toLinear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    static func fromLinear(_ c: Double) -> Double { c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055 }
}

/// OKLCH: perceptual lightness (0...1), chroma (~0...0.37) and hue (degrees).
/// Equal steps look equal to the eye, which keeps generated palettes balanced.
public struct OKLCH: Hashable, Sendable {
    public var l: Double
    public var c: Double
    public var h: Double

    public init(_ l: Double, _ c: Double, _ h: Double) { self.l = l; self.c = c; self.h = h }

    public init(_ rgb: RGBA) {
        let lr = RGBA.toLinear(rgb.r), lg = RGBA.toLinear(rgb.g), lb = RGBA.toLinear(rgb.b)
        let l_ = cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb)
        let m_ = cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb)
        let s_ = cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb)
        let L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
        let A = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
        let B = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
        var hue = atan2(B, A) * 180 / .pi
        if hue < 0 { hue += 360 }
        self.init(L, sqrt(A * A + B * B), hue)
    }

    /// Unclipped sRGB (components may fall outside 0...1).
    func rawRGB() -> (Double, Double, Double) {
        let A = c * cos(h * .pi / 180), B = c * sin(h * .pi / 180)
        let l_ = l + 0.3963377774 * A + 0.2158037573 * B
        let m_ = l - 0.1055613458 * A - 0.0638541728 * B
        let s_ = l - 0.0894841775 * A - 1.2914855480 * B
        let (L, M, S) = (l_ * l_ * l_, m_ * m_ * m_, s_ * s_ * s_)
        let r = 4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S
        let g = -1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S
        let b = -0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S
        return (RGBA.fromLinear(max(0, r)), RGBA.fromLinear(max(0, g)), RGBA.fromLinear(max(0, b)))
    }

    /// sRGB colour, reducing chroma (keeping lightness and hue) until it fits the sRGB gamut.
    public func rgb(alpha: Double = 1) -> RGBA {
        func fits(_ x: OKLCH) -> Bool {
            let (r, g, b) = x.rawRGB()
            return [r, g, b].allSatisfy { $0 >= -0.0005 && $0 <= 1.0005 }
        }
        var lo = 0.0, hi = c
        var best = OKLCH(l, 0, h)
        if fits(self) { best = self } else {
            for _ in 0..<24 {
                let mid = (lo + hi) / 2
                if fits(OKLCH(l, mid, h)) { lo = mid; best = OKLCH(l, mid, h) } else { hi = mid }
            }
        }
        let (r, g, b) = best.rawRGB()
        return RGBA(r: min(1, max(0, r)), g: min(1, max(0, g)), b: min(1, max(0, b)), a: alpha)
    }

    /// Perceptual distance (Euclidean in OKLab).
    public func distance(to o: OKLCH) -> Double {
        let a1 = c * cos(h * .pi / 180), b1 = c * sin(h * .pi / 180)
        let a2 = o.c * cos(o.h * .pi / 180), b2 = o.c * sin(o.h * .pi / 180)
        return sqrt(pow(l - o.l, 2) + pow(a1 - a2, 2) + pow(b1 - b2, 2))
    }
}

public enum ColorMath {
    /// Text for a coloured fill: a dark or a near-white tint of the fill's hue, whichever reads better,
    /// then pushed further if it still misses 4.5:1.
    public static func readableText(on fill: RGBA, hue: Double) -> OKLCH {
        let dark = OKLCH(0.22, 0.03, hue), light = OKLCH(0.99, 0.01, hue)
        let pick = dark.rgb().contrast(with: fill) >= light.rgb().contrast(with: fill) ? dark : light
        return ensureContrast(pick, against: fill, minimum: 4.5)
    }

    /// Moves `fg`'s lightness away from `bg` until the WCAG contrast reaches `minimum`.
    public static func ensureContrast(_ fg: OKLCH, against bg: RGBA, minimum: Double) -> OKLCH {
        var x = fg
        let lighter = OKLCH(bg).l < 0.6
        for _ in 0..<60 where x.rgb().contrast(with: bg) < minimum {
            x.l = min(1, max(0, x.l + (lighter ? 0.01 : -0.01)))
        }
        return x
    }
}
