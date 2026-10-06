import Foundation

/// Maps between a timer dial's angle and minutes. 0° is 12 o'clock, clockwise; one turn = `maxMinutes`.
public enum DialMath {
    public static let minMinutes = 5
    public static let maxMinutes = 120
    public static let step = 5

    /// Minutes for a point relative to the dial centre (y grows downward, as in SwiftUI).
    public static func minutes(dx: Double, dy: Double) -> Int {
        var degrees = atan2(dx, -dy) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        let raw = degrees / 360 * Double(maxMinutes)
        return clamp(Int((raw / Double(step)).rounded()) * step)
    }

    /// Fraction of the ring filled for a number of minutes (0...1).
    public static func fraction(_ minutes: Int) -> Double { Double(clamp(minutes)) / Double(maxMinutes) }

    public static func clamp(_ m: Int) -> Int { min(maxMinutes, max(minMinutes, m)) }

    /// Stops a drag from wrapping across 12 o'clock (120 → 5 or 5 → 120): it pins at the end instead.
    public static func continuing(from previous: Int, to next: Int) -> Int {
        if previous >= maxMinutes - 20 && next <= minMinutes + 20 { return maxMinutes }
        if previous <= minMinutes + 20 && next >= maxMinutes - 20 { return minMinutes }
        return next
    }

    /// Nudges by whole steps (scroll wheel / arrow keys).
    public static func nudge(_ m: Int, by steps: Int) -> Int { clamp((m / step + steps) * step) }
}
