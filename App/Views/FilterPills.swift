import PastelFocusCore
import SwiftUI

/// Today's filter pills: All (always first), one pill per tag on today's tasks, then Done.
/// Drag a tag pill onto another to reorder; the order is saved as the row order of Tags.md.
struct FilterPills: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.theme) var theme
    /// The tag being dragged, its live order while dragging, and where it was grabbed (pointer
    /// minus the pill's centre), so the pill follows the pointer without jumping.
    @State private var dragging: String?
    @State private var order: [String] = []
    @State private var grab: CGSize = .zero
    @State private var pointer: CGPoint = .zero
    @State private var frames: [String: CGRect] = [:]

    private var shown: [String] { dragging == nil ? model.pillTags : order }

    var body: some View {
        // Wraps onto more rows when the tags don't fit, so every pill stays visible.
        FlowLayout(spacing: 8) {
            Button { model.filter = .all } label: { label("All", .all) }.buttonStyle(.plain)
            ForEach(shown, id: \.self) { tag in tagPill(tag) }
            Button { model.filter = .done } label: { label("Done", .done) }.buttonStyle(.plain)
        }
        .coordinateSpace(name: "pills")
        .onPreferenceChange(PillFrames.self) { frames = $0 }
    }

    private func tagPill(_ tag: String) -> some View {
        let isDragged = dragging == tag
        let home = frames[tag].map { CGPoint(x: $0.midX, y: $0.midY) }
        return label(tag.capitalized, .tag(tag))
            .background(GeometryReader { g in Color.clear.preference(key: PillFrames.self, value: [tag: g.frame(in: .named("pills"))]) })
            .shadow(color: .black.opacity(isDragged ? 0.25 : 0), radius: 6, y: 2)
            .offset(isDragged && home != nil ? CGSize(width: pointer.x - grab.width - home!.x, height: pointer.y - grab.height - home!.y) : .zero)
            .zIndex(isDragged ? 1 : 0)
            // The dragged pill tracks the pointer exactly; only the others animate aside.
            .transaction { if isDragged { $0.animation = nil } }
            .contentShape(Capsule())
            .onTapGesture { model.filter = .tag(tag) }
            .gesture(drag(tag))
            .help("Show #\(tag) tasks · drag to reorder")
            .accessibilityAddTraits(.isButton)
    }

    private func drag(_ tag: String) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("pills"))
            .onChanged { v in
                if dragging == nil {
                    let f = frames[tag] ?? CGRect(origin: v.startLocation, size: .zero)
                    order = model.pillTags
                    grab = CGSize(width: v.startLocation.x - f.midX, height: v.startLocation.y - f.midY)
                    dragging = tag
                }
                pointer = v.location
                // Over another tag pill: take its place.
                let centre = CGPoint(x: v.location.x - grab.width, y: v.location.y - grab.height)
                guard let target = order.first(where: { $0 != tag && frames[$0]?.contains(centre) == true }),
                      let from = order.firstIndex(of: tag), let to = order.firstIndex(of: target) else { return }
                var next = order
                next.remove(at: from)
                next.insert(tag, at: to)
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { order = next }
            }
            .onEnded { _ in
                model.reorderPills(order)
                dragging = nil
            }
    }

    private func label(_ text: String, _ f: TaskFilter) -> some View {
        let active = model.filter == f
        return HStack(spacing: 6) {
            Text(text)
            Text("\(model.count(f))").opacity(0.8)
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 16).frame(height: 34)
        .foregroundStyle(active ? theme.onAccent : theme.textSecondary)
        .background(Capsule().fill(active ? AnyShapeStyle(theme.accent) : AnyShapeStyle(theme.elevated)))
        .fixedSize()
    }
}

private struct PillFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
