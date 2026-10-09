import AppKit
import PastelFocusCore
import SwiftUI

/// Timer dial, drawn in the chosen `TimerStyle`. Idle: drag (around a ring or clock, up and down
/// an hourglass or tank) or use the arrow keys to set 5–120 min in 5-min steps. Running: it shows
/// what's left and can't be dragged.
struct TimerDial: View {
    @Environment(\.theme) var theme
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    /// Selected length while idle.
    let minutes: Int
    /// Ring fill while a session runs (nil when idle).
    let progress: Double?
    /// Digits to show while running/paused.
    let clock: String
    let caption: String
    let onCommit: (Int) -> Void
    var size: CGFloat = 112
    /// False in stopwatch mode: there's no length to set.
    var editable = true
    var style: TimerStyle = .ring
    /// Time is passing (not paused or idle) and motion is allowed: the hourglass runs, the tank drips.
    var flowing = false

    /// Value under the finger. Kept after release until `minutes` catches up: the model publishes the new
    /// length a run-loop later, and clearing this early flashed the old value before jumping to the new one.
    @State private var dragMinutes: Int?
    /// Length when an up-and-down drag began.
    @State private var dragStart: Int?
    @FocusState private var focused: Bool

    private var interactive: Bool { editable && progress == nil }
    private var shown: Int { dragMinutes ?? minutes }
    private var fill: Double { progress ?? (editable ? DialMath.fraction(shown) : 0) }
    private let line: CGFloat = 7
    /// How far the grab target reaches past the ring. The knob sits half outside the dial, and a click
    /// that just missed the ring used to fall through to the panel and move the window instead.
    static let hitSlop: CGFloat = 16

    var body: some View {
        Group {
            if style == .ring {
                ZStack { ring; digits(compact: false) }
            } else {
                // The picture on top, the time under it, so neither hides the other.
                let art = artSize
                VStack(spacing: 2) {
                    ZStack {
                        switch style {
                        case .clock:
                            ClockFace(fill: fill, size: art)
                            if interactive { knob(radius: art / 2) }
                        case .hourglass: Hourglass(fill: fill, size: art, flowing: flowing)
                        default: WaterDrip(fill: fill, size: art, dripping: flowing)
                        }
                    }
                    .animation(progress == nil && !reduceMotion ? .interactiveSpring(response: 0.16, dampingFraction: 0.9) : nil, value: fill)
                    digits(compact: true)
                }
            }
        }
        .frame(width: size, height: size, alignment: .top)
        .onChange(of: minutes) { dragMinutes = nil }
        .onChange(of: interactive) { dragMinutes = nil }
        .padding(Self.hitSlop)
        .contentShape(style.isCircular ? AnyShape(Circle()) : AnyShape(Rectangle()))
        .gesture(style.isCircular ? AnyGesture(drag.map { _ in () }) : AnyGesture(verticalDrag.map { _ in () }), including: interactive ? .all : .subviews)
        .padding(-Self.hitSlop) // keeps the layout size; only the hit area grows
        .focusable(interactive)
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(keys: [.upArrow, .rightArrow, .downArrow, .leftArrow]) { press in
            guard interactive else { return .ignored }
            let up = press.key == .upArrow || press.key == .rightArrow
            onCommit(DialMath.nudge(minutes, by: up ? 1 : -1))
            return .handled
        }
        .accessibilityElement()
        .accessibilityLabel(interactive ? "Focus length" : "Time left")
        .accessibilityValue(interactive ? "\(shown) minutes" : clock)
        .accessibilityAdjustableAction { dir in
            guard interactive else { return }
            onCommit(DialMath.nudge(minutes, by: dir == .increment ? 1 : -1))
        }
        .help(interactive ? (style.isCircular ? "Drag around the dial or use the arrow keys to set the length"
                                                : "Drag up or down, or use the arrow keys, to set the length") : "")
    }

    /// Side of the picture for the non-ring styles, which sit above the digits.
    private var artSize: CGFloat { size * 0.7 }

    private func digits(compact: Bool) -> some View {
        VStack(spacing: 0) {
            Text(interactive ? String(format: "%d:00", shown) : clock)
                .font(.system(size: (interactive || clock.count <= 5 ? 24 : 19) * (compact ? 0.72 : 1), weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(theme.isNight ? theme.accent : theme.textPrimary)
            if !compact { Text(caption).font(.system(size: 10, weight: .medium)).foregroundStyle(theme.textSecondary) }
        }
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(theme.track, lineWidth: line)
            ticks
            ZStack {
                Circle()
                    .trim(from: 0, to: fill)
                    .stroke(theme.accent, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if interactive { knob(radius: size / 2) }
            }
            // Glide between 5-minute steps while dragging (ring and knob move together along the arc).
            // A running ring moves a hair per second and isn't animated: that cost ~3% CPU for nothing.
            .animation(progress == nil && !reduceMotion ? .interactiveSpring(response: 0.16, dampingFraction: 0.9) : nil, value: fill)
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                // The clock sits at the top, above its digits; the ring fills the dial.
                let cx = size / 2 + Self.hitSlop, cy = (style == .clock ? artSize : size) / 2 + Self.hitSlop
                let raw = DialMath.minutes(dx: v.location.x - cx, dy: v.location.y - cy)
                let next = DialMath.continuing(from: dragMinutes ?? minutes, to: raw)
                if next != dragMinutes {
                    dragMinutes = next
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
            }
            .onEnded { _ in
                guard let m = dragMinutes else { return }
                if m == minutes { dragMinutes = nil } else { onCommit(m) } // cleared once `minutes` arrives
            }
    }

    private var verticalDrag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
                let start = dragStart ?? (dragMinutes ?? minutes)
                if dragStart == nil { dragStart = start }
                let next = DialMath.nudge(start, by: Int((-v.translation.height / 8).rounded()))
                if next != dragMinutes {
                    dragMinutes = next
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
            }
            .onEnded { _ in
                dragStart = nil
                guard let m = dragMinutes else { return }
                if m == minutes { dragMinutes = nil } else { onCommit(m) }
            }
    }

    /// Quarter-hour ticks.
    private var ticks: some View {
        ForEach(0..<8) { i in
            Capsule().fill(theme.textTertiary.opacity(0.5)).frame(width: 1.5, height: 4)
                .offset(y: -(size / 2) + line + 5)
                .rotationEffect(.degrees(Double(i) * 45))
        }
    }

    private func knob(radius: CGFloat) -> some View {
        // Rotated rather than offset so an animated change travels along the ring, not across it.
        // Same accent as the ring, outlined in the panel colour so it stands out against it.
        Circle().fill(theme.accent)
            .overlay(Circle().strokeBorder(theme.surface, lineWidth: 2.5))
            .frame(width: 15, height: 15)
            .offset(y: -radius)
            .rotationEffect(.degrees(DialMath.fraction(shown) * 360))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1) // after rotating, so it always falls downward
    }
}
