import PastelFocusCore
import SwiftUI

/// Settings → Tags: the tags on your task lines and the plant each one grows.
struct TagsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.snapshotMode) var snapshot
    @State private var newTag = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The first tag on a task line decides the plant it grows (#later marks priority and is skipped). Tags you or Hermes write are added here automatically. Several tags can share a plant. Drag to reorder: the Today panel's filter pills follow this order.")
                .font(.callout).foregroundStyle(.secondary)
            if model.tags.tags.isEmpty {
                Text("No tags yet. Add one below, or tag a task like “Read chapter 3 #learning”.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if snapshot { // offscreen renders can't draw List
                VStack(alignment: .leading, spacing: 6) { ForEach(model.tags.tags) { TagRow(tag: $0) } }
                Spacer()
            } else {
                List {
                    ForEach(model.tags.tags) { TagRow(tag: $0) }
                        .onMove { from, to in model.changeTags { c in try c.updateTags { $0.move(fromOffsets: from, toOffset: to) } } }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
            HStack {
                TextField("New tag, e.g. reading", text: $newTag).textFieldStyle(.roundedBorder).onSubmit(add)
                Button("Add", action: add).disabled(TagRegistry.normalize(newTag).isEmpty)
            }
        }
        .padding(20)
    }

    private func add() {
        let name = newTag
        if model.changeTags({ c in try c.updateTags { try $0.add(name) } }) { newTag = "" }
    }
}

private struct TagRow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.plantArt) var art
    @Environment(\.theme) var theme
    let tag: TagDefinition
    @State private var renaming = false
    @State private var newName = ""
    @State private var picking = false

    var body: some View {
        let uses = model.taskCount(tagged: tag.name)
        let slot = tag.slot(inTheme: art.theme)
        HStack(spacing: 12) {
            Button { picking = true } label: {
                HStack(spacing: 6) {
                    SpriteView(rows: PlantDesigns.sprite(slot, theme: art.theme), px: 3)
                    Text(slot.letter).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .help("Choose the plant this tag grows")
            .popover(isPresented: $picking, arrowEdge: .bottom) { SlotPicker(tag: tag) }

            if renaming {
                TextField("Tag name", text: $newName).textFieldStyle(.roundedBorder).frame(width: 180)
                    .onSubmit(rename).onExitCommand { renaming = false }
                Button("Save", action: rename)
            } else {
                Text("#\(tag.name)").font(.system(size: 13, weight: .medium))
                if tag.overrides[art.theme] != nil {
                    Text("own plant in \(theme.definition.name)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(uses == 0 ? "unused" : "\(uses) task\(uses == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
            Button { newName = tag.name; renaming = true } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless).help("Rename (also updates every task line using it)")
            Button { model.changeTags { try $0.removeTag(tag.name) } } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).disabled(uses > 0)
                .help(uses > 0 ? "In use: rename it, or remove it from those tasks first" : "Remove this tag")
        }
        .padding(.vertical, 2)
    }

    private func rename() {
        let old = tag.name, new = newName
        if model.changeTags({ try $0.renameTag(old, to: new) }) { renaming = false }
    }
}

/// The ten plants for the current theme. Picks for all themes, or just this one.
private struct SlotPicker: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.plantArt) var art
    @Environment(\.theme) var theme
    @Environment(\.dismiss) var dismiss
    let tag: TagDefinition
    @State private var onlyThisTheme = false

    var body: some View {
        let current = tag.slot(inTheme: art.theme)
        VStack(alignment: .leading, spacing: 12) {
            Text("#\(tag.name) grows").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 8), count: 5), spacing: 8) {
                ForEach(Slot.allCases, id: \.self) { slot in
                    Button { choose(slot) } label: {
                        VStack(spacing: 4) {
                            SpriteView(rows: PlantDesigns.sprite(slot, theme: art.theme), px: 4).frame(height: 34)
                            Text("\(slot.letter) · \(PlantDesigns.name(slot, theme: art.theme))")
                                .font(.system(size: 9)).lineLimit(2).multilineTextAlignment(.center)
                        }
                        .frame(width: 64, height: 66)
                        .background(RoundedRectangle(cornerRadius: 8).fill(slot == current ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(slot == current ? Color.accentColor : .clear, lineWidth: 1.5))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Toggle("Only in \(theme.definition.name)", isOn: $onlyThisTheme)
                .help("Off: the choice applies to every theme. On: this theme gets its own plant for this tag.")
            if tag.overrides[art.theme] != nil {
                Button("Use the same plant as other themes") {
                    model.changeTags { c in try c.updateTags { $0.setOverride(nil, for: tag.name, theme: art.theme) } }
                    dismiss()
                }
                .buttonStyle(.link)
            }
        }
        .padding(16)
        .onAppear { onlyThisTheme = tag.overrides[art.theme] != nil }
    }

    private func choose(_ slot: Slot) {
        let name = tag.name, themeID = art.theme, only = onlyThisTheme
        model.changeTags { c in
            try c.updateTags { r in
                if only { r.setOverride(slot, for: name, theme: themeID) } else { r.setSlot(slot, for: name) }
            }
        }
        dismiss()
    }
}
