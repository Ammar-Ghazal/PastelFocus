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
            let r = ImageRenderer(content: view.environmentObject(model).environmentObject(model.ticks).environment(\.snapshotMode, true).padding(20).background(Color(hex: 0x6B5A7A)))
            r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("\(name).png"))
            }
        }
        // One dark and one light combo per theme, plus the shared detail views in the default theme.
        for def_ in ThemeCatalog.all {
            for p in [def_.palettes.first { $0.isDark }, def_.palettes.first { !$0.isDark }].compactMap({ $0 }) {
                let t = Theme(def_, p), tag = "\(def_.id)-\(p.isDark ? "dark" : "light")"
                save("theme-\(tag)-today", TodayView().environment(\.theme, t))
                save("theme-\(tag)-focus", FocusView().environment(\.theme, t))
                save("theme-\(tag)-garden", ProgressPanelView().environment(\.theme, t))
            }
        }
        let t = model.theme
        save("dial-idle", TimerDial(minutes: 40, progress: nil, clock: "", caption: "min", onCommit: { _ in }).padding(10).environment(\.theme, t))
        save("dial-stopwatch", TimerDial(minutes: 25, progress: 0.3, clock: "18:05", caption: "elapsed", onCommit: { _ in }, editable: false).padding(10).environment(\.theme, t))
        let demo = AppSettings()
        demo.savedReasons = [StopReasons.shorten("Phone call from family"), StopReasons.shorten("Had to pick up my brother from school")]
        save("stop-reason", StopReasonCard(settings: demo, done: { _ in }, cancel: {}).frame(width: 280).environment(\.theme, t))
        save("appearance", AppearanceView(settings: settings).frame(width: 760, height: 640).environment(\.theme, t))
    }

    /// Default layout matches the reference image: Today on the left, Focus and Garden stacked on the right.
    private func showPanels() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        if settings.showToday {
            panels.show("today", size: CGSize(width: 560, height: 690), origin: CGPoint(x: screen.minX + 260, y: screen.maxY - 760), floating: settings.floatPanels) {
                Themed { TodayView() }.environmentObject(model)
            }
        } else { panels.hide("today") }
        if settings.showFocus {
            panels.show("focus", size: CGSize(width: 300, height: 230), origin: CGPoint(x: screen.maxX - 340, y: screen.maxY - 520), floating: settings.floatPanels) {
                Themed { FocusView() }.environmentObject(model).environmentObject(model.ticks)
            }
        } else { panels.hide("focus") }
        if settings.showProgress {
            panels.show("progress", size: CGSize(width: 380, height: 280), origin: CGPoint(x: screen.maxX - 420, y: screen.maxY - 330), floating: settings.floatPanels) {
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
    }
}
