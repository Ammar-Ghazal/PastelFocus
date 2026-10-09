import PastelFocusCore
import SwiftUI

/// After a focus session: how much of the whole task is done now? 100% completes it.
struct ProgressCard: View {
    @Environment(\.theme) var theme
    let prompt: ProgressPrompt
    let answer: (Int?) -> Void
    @State private var value: Double

    init(prompt: ProgressPrompt, answer: @escaping (Int?) -> Void) {
        self.prompt = prompt
        self.answer = answer
        _value = State(initialValue: Double(prompt.current ?? 50))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How far along is \u{201C}\(prompt.title)\u{201D}?")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.textPrimary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Text("The whole task, not just this session.").font(.system(size: 11)).foregroundStyle(theme.textSecondary)
            HStack(spacing: 8) {
                Slider(value: $value, in: 0...100, step: 5).tint(theme.accent)
                    .accessibilityLabel("Task progress")
                    .accessibilityValue("\(Int(value)) percent")
                Text("\(Int(value))%").font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(theme.textPrimary).frame(width: 38, alignment: .trailing)
            }
            HStack(spacing: 10) {
                Button("Save") { answer(Int(value)) }.buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.onAccent)
                    .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(theme.accent))
                    .keyboardShortcut(.defaultAction)
                Button("It's done") { answer(100) }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(theme.accent)
                    .help("Marks the task done everywhere")
                Spacer()
                Button("Skip") { answer(nil) }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(theme.textSecondary)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(theme.elevated))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.borderActive))
        .padding(6)
    }
}
