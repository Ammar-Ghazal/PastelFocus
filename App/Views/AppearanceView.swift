import PastelFocusCore
import SwiftUI

/// Settings → Appearance: pick a theme (scene) and one of its colour combos. Changes apply live.
struct AppearanceView: View {
    @ObservedObject var settings: AppSettings
    @EnvironmentObject var model: AppModel
    @State private var mode: ModeFilter = .all
    @Environment(\.snapshotMode) private var snapshot

    enum ModeFilter: String, CaseIterable { case all = "All", dark = "Dark", light = "Light" }

    private var selected: ThemeDefinition { ThemeCatalog.resolve(settings.themeSelection).0 }

    var body: some View {
        if snapshot { content } else { ScrollView { content } }
    }

    private var content: some View {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 18) {
                    Toggle("Ambient motion", isOn: $settings.ambientMotion)
                        .help("Twinkling stars, falling petals, snow… Off keeps the scene still. Reduce Motion also turns it off.")
                    Toggle("Match macOS light/dark", isOn: $settings.matchSystemAppearance)
                        .help("Switch to this theme's closest light or dark combo when macOS changes appearance.")
                    Spacer()
                    Button("Surprise me") { surprise() }
                }
                .onChange(of: settings.ambientMotion) { _, _ in model.objectWillChange.send() }

                Text("Theme").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 168), spacing: 12)], spacing: 12) {
                    ForEach(ThemeCatalog.all) { t in
                        ThemeCard(definition: t, palette: t.id == selected.id ? model.theme.palette : t.defaultPalette,
                                  selected: t.id == selected.id) { model.selectTheme(t.id) }
                    }
                }

                HStack {
                    Text("\(selected.name) colour combos").font(.headline)
                    Text("\(selected.palettes.count)").foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $mode) { ForEach(ModeFilter.allCases, id: \.self) { Text($0.rawValue) } }
                        .pickerStyle(.segmented).frame(width: 200)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10) {
                    ForEach(filtered) { p in
                        PaletteChip(definition: selected, palette: p, selected: p.id == settings.themeSelection.paletteID) {
                            model.selectPalette(p.id)
                        }
                    }
                }
            }
            .padding(20)
    }

    private var filtered: [Palette] {
        selected.palettes.filter { mode == .all || $0.isDark == (mode == .dark) }
    }

    private func surprise() {
        let t = ThemeCatalog.all.randomElement()!
        settings.themeSelection = ThemeSelection(themeID: t.id, paletteID: t.palettes.randomElement()!.id)
    }
}

/// A theme's scene in miniature with its name, in one of its palettes.
struct ThemeCard: View {
    let definition: ThemeDefinition
    let palette: Palette
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let t = Theme(definition, palette)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                SceneArt(theme: t).frame(height: 84).overlay(alignment: .bottomLeading) {
                    Text(definition.name).font(t.titleFont(14, .semibold)).foregroundStyle(t.textPrimary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(t.glassTint)).padding(8)
                }
                HStack(spacing: 3) {
                    ForEach(Array(palette.swatches.dropFirst(2).prefix(6).enumerated()), id: \.offset) { _, c in
                        Circle().fill(Color(c)).frame(width: 9, height: 9)
                    }
                    Spacer()
                    Text("\(definition.palettes.count)").font(.system(size: 10, weight: .medium)).foregroundStyle(t.textSecondary)
                }
                .padding(8)
                .background(t.surface)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            // The scene art ignores hits (so it never steals clicks elsewhere); without this only the
            // name pill and the swatch bar were clickable.
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? t.accent : Color.secondary.opacity(hover ? 0.5 : 0.2), lineWidth: selected ? 2.5 : 1))
            .scaleEffect(hover ? 1.02 : 1)
            .animation(.easeOut(duration: 0.12), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(definition.summary)
        .accessibilityLabel("\(definition.name) theme\(selected ? ", selected" : "")")
    }
}

/// A colour combo as a mini panel: surface, title, accent button, tag chips.
struct PaletteChip: View {
    let definition: ThemeDefinition
    let palette: Palette
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let t = Theme(definition, palette)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Today").font(t.titleFont(13)).foregroundStyle(t.accent)
                    Spacer()
                    Circle().fill(t.accent).frame(width: 14, height: 14)
                        .overlay(Image(systemName: "play.fill").font(.system(size: 6)).foregroundStyle(t.onAccent))
                }
                RoundedRectangle(cornerRadius: 3).fill(t.highlight).frame(height: 8)
                HStack(spacing: 3) {
                    ForEach([t.tagFocus, t.tagHealth, t.tagLater, t.tagHigh, t.tagLearning].indices, id: \.self) { i in
                        Capsule().fill([t.tagFocus, t.tagHealth, t.tagLater, t.tagHigh, t.tagLearning][i]).frame(width: 14, height: 5)
                    }
                }
                Text(palette.name).font(.system(size: 11, weight: .medium)).foregroundStyle(t.textPrimary).lineLimit(1)
            }
            .padding(9)
            .background(LinearGradient(colors: [t.sceneTop, t.sceneBottom], startPoint: .top, endPoint: .bottom))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? t.accent : t.border, lineWidth: selected ? 2.5 : 1))
            .overlay(alignment: .topTrailing) {
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(t.accent, t.onAccent).padding(4) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(palette.name), \(palette.isDark ? "dark" : "light")\(selected ? ", selected" : "")")
    }
}
