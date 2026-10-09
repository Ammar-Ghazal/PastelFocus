import PastelFocusCore
import SwiftUI

/// The Focus panel's task title, which opens the task dropdown when clicked.
struct TaskPickerButton: View {
    @Environment(\.theme) var theme
    let title: String
    let open: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.textPrimary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                if enabled {
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(theme.textSecondary)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help("Choose the task to focus on")
        .accessibilityLabel("Task: \(title)")
        .accessibilityHint("Opens the task list")
    }
}

/// Dropdown of today's open tasks. During a session, picking one moves the session to it.
struct TaskPickerList: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.theme) var theme
    let close: () -> Void
    @State private var hovered: String?

    private var currentID: String? { model.activeTaskID ?? (model.focusInSession ? nil : model.selectedTaskID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.focusInSession ? "Move this session to…" : "Focus on…")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
            // Scrolls only when the list is taller than the panel leaves room for.
            ViewThatFits(in: .vertical) {
                rows
                ScrollView(showsIndicators: false) { rows }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 150, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.elevated))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.borderActive))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        .onExitCommand(perform: close)
    }

    private var rows: some View {
        VStack(spacing: 2) {
            ForEach(model.openTasks) { t in row(t.title, detail: t.subtitle, id: t.taskID, tag: t.category) { model.selectTask(t) } }
            row("No task (Unassigned)", detail: nil, id: nil, tag: nil) { model.selectTask(nil) }
        }
        .padding(.horizontal, 6).padding(.bottom, 6)
    }

    private func row(_ title: String, detail: String?, id: String?, tag: String?, pick: @escaping () -> Void) -> some View {
        let current = id == currentID
        let key = id ?? "none"
        return Button { pick(); close() } label: {
            HStack(spacing: 8) {
                Image(systemName: current ? "checkmark" : "circle").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(current ? theme.accent : theme.textTertiary).frame(width: 14)
                (Text(title).font(.system(size: 12, weight: current ? .semibold : .regular)).foregroundStyle(theme.textPrimary)
                 + Text(detail.map { "  \($0)" } ?? "").font(.system(size: 11)).foregroundStyle(theme.textSecondary))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let tag { Text("#\(tag)").font(.system(size: 10)).foregroundStyle(theme.textTertiary).lineLimit(1) }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(hovered == key ? theme.track.opacity(0.7) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? key : (hovered == key ? nil : hovered) }
        .accessibilityAddTraits(current ? .isSelected : [])
    }
}
