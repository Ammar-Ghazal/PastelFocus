import AppKit
import PastelFocusCore
import SwiftUI

/// Circular timer dial. Idle: drag the ring (or use arrow keys) to set 5–120 min in 5-min steps.
/// Running: the ring shows what's left and can't be dragged.
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

    /// Value under the finger. Kept after release until `minutes` catches up: the model publishes the new
    /// length a run-loop later, and clearing this early flashed the old value before jumping to the new one.
    @State private var dragMinutes: Int?
    @FocusState private var focused: Bool

    private var interactive: Bool { editable && progress == nil }
    private var shown: Int { dragMinutes ?? minutes }
    private var fill: Double { progress ?? (editable ? DialMath.fraction(shown) : 0) }
    private let line: CGFloat = 7
    /// How far the grab target reaches past the ring. The knob sits half outside the dial, and a click
    /// that just missed the ring used to fall through to the panel and move the window instead.
    static let hitSlop: CGFloat = 16

    var body: some View {
        ZStack {
            Circle().stroke(theme.track, lineWidth: line)
            ticks
            ZStack {
                Circle()
                    .trim(from: 0, to: fill)
                    .stroke(theme.accent, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if interactive { knob }
            }
            // Glide between 5-minute steps while dragging (ring and knob move together along the arc).
            // A running ring moves a hair per second and isn't animated: that cost ~3% CPU for nothing.
            .animation(progress == nil && !reduceMotion ? .interactiveSpring(response: 0.16, dampingFraction: 0.9) : nil, value: fill)
            VStack(spacing: 0) {
                Text(interactive ? String(format: "%d:00", shown) : clock)
                    .font(.system(size: interactive || clock.count <= 5 ? 24 : 19, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(theme.isNight ? theme.accent : theme.textPrimary)
                Text(caption).font(.system(size: 10, weight: .medium)).foregroundStyle(theme.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .onChange(of: minutes) { dragMinutes = nil }
        .onChange(of: interactive) { dragMinutes = nil }
        .padding(Self.hitSlop)
        .contentShape(Circle())
        .gesture(drag, including: interactive ? .all : .subviews)
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
        .help(interactive ? "Drag the ring or use the arrow keys to set the length" : "")
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let centre = size / 2 + Self.hitSlop
                let raw = DialMath.minutes(dx: v.location.x - centre, dy: v.location.y - centre)
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

    /// Quarter-hour ticks.
    private var ticks: some View {
        ForEach(0..<8) { i in
            Capsule().fill(theme.textTertiary.opacity(0.5)).frame(width: 1.5, height: 4)
                .offset(y: -(size / 2) + line + 5)
                .rotationEffect(.degrees(Double(i) * 45))
        }
    }

    private var knob: some View {
        // Rotated rather than offset so an animated change travels along the ring, not across it.
        // Same accent as the ring, outlined in the panel colour so it stands out against it.
        Circle().fill(theme.accent)
            .overlay(Circle().strokeBorder(theme.surface, lineWidth: 2.5))
            .frame(width: 15, height: 15)
            .offset(y: -size / 2)
            .rotationEffect(.degrees(DialMath.fraction(shown) * 360))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1) // after rotating, so it always falls downward
    }
}
