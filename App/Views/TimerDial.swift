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

    @State private var dragMinutes: Int?
    @FocusState private var focused: Bool

    private var interactive: Bool { editable && progress == nil }
    private var shown: Int { dragMinutes ?? minutes }
    private var fill: Double { progress ?? (editable ? DialMath.fraction(shown) : 0) }
    private let line: CGFloat = 7

    var body: some View {
        ZStack {
            Circle().stroke(theme.track, lineWidth: line)
            ticks
            Circle()
                .trim(from: 0, to: fill)
                .stroke(LinearGradient(colors: [theme.accent, theme.accentLight], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // Ease only when the length is changed on the dial; a running ring moves a hair per
                // second, and animating that every second cost ~3% CPU for no visible benefit.
                .animation(progress == nil && dragMinutes == nil && !reduceMotion ? .easeOut(duration: 0.2) : nil, value: fill)
            if interactive { knob }
            VStack(spacing: 0) {
                Text(interactive ? String(format: "%d:00", shown) : clock)
                    .font(.system(size: interactive || clock.count <= 5 ? 24 : 19, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(theme.isNight ? theme.accentLight : theme.textPrimary)
                Text(caption).font(.system(size: 10, weight: .medium)).foregroundStyle(theme.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(drag, including: interactive ? .all : .subviews)
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
                let raw = DialMath.minutes(dx: v.location.x - size / 2, dy: v.location.y - size / 2)
                let next = DialMath.continuing(from: dragMinutes ?? minutes, to: raw)
                if next != dragMinutes {
                    dragMinutes = next
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
            }
            .onEnded { _ in
                if let m = dragMinutes { onCommit(m) }
                dragMinutes = nil
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
        let angle = DialMath.fraction(shown) * 2 * .pi
        let r = size / 2
        return Circle().fill(theme.accentLight)
            .overlay(Circle().strokeBorder(theme.accentStrong, lineWidth: 2))
            .frame(width: 15, height: 15)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .offset(x: r * sin(angle), y: -r * cos(angle))
    }
}
