import PastelFocusCore
import SwiftUI

/// Today's filter pills: All (always first), one pill per tag on listed tasks, then Done.
/// Drag a tag pill to reorder; the order is saved as the row order of Tags.md.
///
/// While dragging, the pill's slot in the layout stays as an empty placeholder and a floating copy
/// follows the pointer. The copy's position depends only on the pointer, never on where the slot
/// was laid out, so it can't jump when the other pills move aside.
struct FilterPills: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.theme) var theme
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var drag: PillDrag?
    @State private var frames: [String: CGRect] = [:]

    private var shown: [String] { drag?.order ?? model.pillTags }

    var body: some View {
        // Wraps onto more rows when the tags don't fit, so every pill stays visible.
        FlowLayout(spacing: 8) {
            Button { model.filter = .all } label: { label("All", .all) }.buttonStyle(.plain)
            ForEach(shown, id: \.self) { tag in tagPill(tag) }
            Button { model.filter = .done } label: { label("Done", .done) }.buttonStyle(.plain)
        }
        .coordinateSpace(name: "pills")
        .onPreferenceChange(PillFrames.self) { frames = $0 }
        .overlay(alignment: .topLeading) {
            if let d = drag {
                label(d.tag.capitalized, .tag(d.tag))
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                    .scaleEffect(d.dropping ? 1 : 1.04)
                    .position(d.centre)
                    .allowsHitTesting(false)
            }
        }
    }

    private func tagPill(_ tag: String) -> some View {
        label(tag.capitalized, .tag(tag))
            .opacity(drag?.tag == tag ? 0 : 1) // the slot it will drop into
            .background(GeometryReader { g in Color.clear.preference(key: PillFrames.self, value: [tag: g.frame(in: .named("pills"))]) })
            .contentShape(Capsule())
            .onTapGesture { model.filter = .tag(tag) }
            .gesture(dragGesture(tag))
            .help("Show #\(tag) tasks · drag to reorder")
            .accessibilityAddTraits(.isButton)
            .accessibilityActions {
                if let i = shown.firstIndex(of: tag) {
                    if i > 0 { Button("Move left") { move(tag, to: i - 1) } }
                    if i < shown.count - 1 { Button("Move right") { move(tag, to: i + 1) } }
                }
            }
    }

    private func dragGesture(_ tag: String) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("pills"))
            .onChanged { v in
                if drag == nil {
                    guard let f = frames[tag] else { return }
                    drag = PillDrag(tag: tag, order: model.pillTags,
                                    grab: CGSize(width: v.startLocation.x - f.midX, height: v.startLocation.y - f.midY),
                                    pointer: v.location)
                }
                drag?.pointer = v.location
                guard let d = drag, let to = PillReorder.insertionIndex(of: tag, in: d.order, at: d.centre, frames: frames),
                      to != d.order.firstIndex(of: tag) else { return }
                withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86)) {
                    drag?.order = PillReorder.moving(tag, to: to, in: d.order)
                }
            }
            .onEnded { _ in
                guard let d = drag else { return }
                model.reorderPills(d.order)
                // Settle the floating copy onto its slot, then show the real pill there.
                guard !reduceMotion, let slot = frames[tag] else { drag = nil; return }
                drag?.dropping = true
                withAnimation(.easeOut(duration: 0.16)) {
                    drag?.pointer = CGPoint(x: slot.midX + d.grab.width, y: slot.midY + d.grab.height)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { if drag?.tag == tag { drag = nil } }
            }
    }

    private func move(_ tag: String, to index: Int) {
        model.reorderPills(PillReorder.moving(tag, to: index, in: shown))
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

/// A pill being dragged: its live order, where it was grabbed (pointer minus the pill's centre)
/// and the pointer, all in the pills' coordinate space.
private struct PillDrag {
    let tag: String
    var order: [String]
    let grab: CGSize
    var pointer: CGPoint
    var dropping = false
    var centre: CGPoint { CGPoint(x: pointer.x - grab.width, y: pointer.y - grab.height) }
}

private struct PillFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
