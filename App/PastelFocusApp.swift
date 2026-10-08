import AppKit
import Combine
import PastelFocusCore
import SwiftUI

@main
struct PastelFocusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra {
            Themed { MenuBarContent() }.environmentObject(delegate.model)
        } label: {
            MenuBarLabel().environmentObject(delegate.model).environmentObject(delegate.model.ticks)
        }
        Window("Insights", id: "insights") {
            Themed { InsightsView() }.environmentObject(delegate.model)
        }
        Settings {
            Themed { SettingsView(settings: delegate.settings) }.environmentObject(delegate.model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    lazy var model = AppModel(settings: settings)
    private let panels = PanelController()
    private var bag: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = model
        if let i = CommandLine.arguments.firstIndex(of: "--render-snapshots"), i + 1 < CommandLine.arguments.count {
            renderSnapshots(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
            NSApp.terminate(nil)
            return
        }
        showPanels()
        settings.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.showPanels() } }.store(in: &bag)
    }

    /// Debug/verification: draws each panel offscreen to PNG (`PastelFocus --render-snapshots <dir>`).
    private func renderSnapshots(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func save<V: View>(_ name: String, _ view: V) {
            let r = ImageRenderer(content: view.environmentObject(model).environmentObject(model.ticks).environment(\.plantArt, model.plantArt).environment(\.snapshotMode, true).padding(20).background(Color(hex: 0x6B5A7A)))
            r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("\(name).png"))
            }
        }
        // Windows with native controls (text fields, pickers), which ImageRenderer can't draw: lay them out
        // in an offscreen window that is never shown, and capture the view itself.
        func saveWindow<V: View>(_ name: String, size: CGSize, _ view: V) {
            let host = NSHostingView(rootView: Themed { view }.environmentObject(model))
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
            w.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
            }
        }
        if var demo = TaskLineParser.parse("- [/] Practice a mock interview — 45 min with a timer #career #learning [est:: 2] [sessions:: 1] 🔺 📅 2026-10-10 🆔 demo",
                                           file: "Daily Plans/2026-10-08.md") {
            demo.notes = ["Use the STAR outline", "Record it"]
            saveWindow("task-editor", size: CGSize(width: 460, height: 900), TaskEditorView(original: demo, close: {}))
        }
        // One dark and one light combo per theme, plus the shared detail views in the default theme.
        for def_ in ThemeCatalog.all {
            for p in [def_.palettes.first { $0.isDark }, def_.palettes.first { !$0.isDark }].compactMap({ $0 }) {
                let t = Theme(def_, p), tag = "\(def_.id)-\(p.isDark ? "dark" : "light")"
                save("theme-\(tag)-today", TodayView().frame(height: TodayView.defaultHeight).environment(\.theme, t))
                save("theme-\(tag)-focus", FocusView().environment(\.theme, t))
                save("theme-\(tag)-garden", ProgressPanelView().environment(\.theme, t))
            }
        }
        let t = model.theme
        save("today-min-height", TodayView().frame(height: TodayView.heightRange.lowerBound).environment(\.theme, t))
        save("dial-idle", TimerDial(minutes: 40, progress: nil, clock: "", caption: "min", onCommit: { _ in }).padding(10).environment(\.theme, t))
        save("dial-stopwatch", TimerDial(minutes: 25, progress: 0.3, clock: "18:05", caption: "elapsed", onCommit: { _ in }, editable: false).padding(10).environment(\.theme, t))
        let demo = AppSettings()
        demo.savedReasons = [StopReasons.shorten("Phone call from family"), StopReasons.shorten("Had to pick up my brother from school")]
        save("stop-reason", StopReasonCard(settings: demo, done: { _ in }, cancel: {}).frame(width: 280).environment(\.theme, t))
        save("appearance", AppearanceView(settings: settings).frame(width: 760, height: 640).environment(\.theme, t))
        save("tags", TagsView().frame(width: 760, height: 420).environment(\.theme, t))
        save("slots", HStack(spacing: 14) {
            ForEach(Slot.allCases, id: \.self) { slot in
                VStack(spacing: 6) {
                    SpriteView(rows: PlantDesigns.sprite(slot, theme: t.definition.id), px: 6)
                    Text("\(slot.letter) · \(PlantDesigns.name(slot, theme: t.definition.id))").font(.system(size: 10)).foregroundStyle(t.textSecondary)
                }
            }
        }.padding(16).background(t.surface).environment(\.theme, t))
        // Garden plots from 2 to 120 sessions, to check how the plot grows and zooms out.
        let cal = model.coordinator.calendar, today = model.coordinator.today
        let cats = ["coding", "learning", "health", "personal", nil]
        for n in [2, 12, 40, 120] {
            let sessions = (0..<n).map { i -> SessionRecord in
                let start = cal.startOfDay(cal.addDays(-(i % 28), to: today))!.addingTimeInterval(Double(9 * 3600 + i * 60))
                let minutes = [25, 45, 80, 15][i % 4]
                return SessionRecord(id: "demo-\(i)", kind: i % 17 == 5 ? .nsdr : .focus, taskId: nil, taskTitle: nil, category: cats[i % 5],
                                     preset: "25/5", plannedS: minutes * 60, startedAt: start, endedAt: start.addingTimeInterval(Double(minutes * 60)),
                                     tz: cal.timeZone.identifier, focusedS: minutes * 60, outcome: i % 9 == 4 ? .stoppedEarly : .completed, pauses: [])
            }
            let g = GardenBuilder.build(sessions: sessions, events: [], calendar: cal, now: Date())
            save("garden-\(n)", IsoPlotView(plot: g.plot(.month, containing: today, calendar: cal), animate: false).frame(width: 340, height: 190).environment(\.theme, t))
        }
    }

    /// Default layout matches the reference image: Today on the left, Focus and Garden stacked on the right.
    private func showPanels() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        if settings.showToday {
            panels.show("today", size: CGSize(width: 560, height: TodayView.defaultHeight), origin: CGPoint(x: screen.minX + 260, y: screen.maxY - 760),
                        floating: settings.floatPanels, heightRange: TodayView.heightRange) {
                Themed { TodayView() }.environmentObject(model)
            }
        } else { panels.hide("today") }
        if settings.showFocus {
            panels.show("focus", size: CGSize(width: 300, height: 200), origin: CGPoint(x: screen.maxX - 340, y: screen.maxY - 520), floating: settings.floatPanels) {
                Themed { FocusView() }.environmentObject(model).environmentObject(model.ticks)
            }
        } else { panels.hide("focus") }
        if settings.showProgress {
            panels.show("progress", size: CGSize(width: 380, height: 300), origin: CGPoint(x: screen.maxX - 420, y: screen.maxY - 330), floating: settings.floatPanels) {
                Themed { ProgressPanelView() }.environmentObject(model)
            }
        } else { panels.hide("progress") }
        panels.setFloating(settings.floatPanels)
    }
}

/// Applies the current theme and motion setting to a view tree; re-evaluates only when they change,
/// so switching themes updates every panel in place.
struct Themed<Content: View>: View {
    @EnvironmentObject var model: AppModel
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .environment(\.theme, model.theme)
            .environment(\.ambientMotion, model.settings.ambientMotion)
            .environment(\.plantArt, model.plantArt)
    }
}
