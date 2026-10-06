import AppKit
import Combine
import PastelFocusCore
import SwiftUI

@main
struct PastelFocusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent().environmentObject(delegate.model)
        } label: {
            MenuBarLabel().environmentObject(delegate.model)
        }
        Window("Insights", id: "insights") {
            InsightsView().environmentObject(delegate.model).environment(\.theme, .night)
        }
        Settings {
            SettingsView(settings: delegate.settings).environmentObject(delegate.model)
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
        DistributedNotificationCenter.default().addObserver(forName: .init("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.showPanels(force: true) }
        }
    }

    private var theme: Theme {
        switch settings.themeMode {
        case "day": return .day
        case "system": return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .night : .day
        default: return .night
        }
    }

    private var appliedTheme = ""

    /// Debug/verification: draws each panel offscreen to PNG (`PastelFocus --render-snapshots <dir>`).
    private func renderSnapshots(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func save<V: View>(_ name: String, _ view: V) {
            let r = ImageRenderer(content: view.environmentObject(model).environment(\.snapshotMode, true).padding(20).background(Color(hex: 0x6B5A7A)))
            r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("\(name).png"))
            }
        }
        for (suffix, t) in [("night", Theme.night), ("day", Theme.day)] {
            save("today-\(suffix)", TodayView().environment(\.theme, t))
            save("focus-\(suffix)", FocusView().environment(\.theme, t))
            save("garden-\(suffix)", ProgressPanelView().environment(\.theme, t))
            save("dial-idle-\(suffix)", TimerDial(minutes: 40, progress: nil, clock: "", caption: "min", onCommit: { _ in }).padding(10).environment(\.theme, t))
            let demo = AppSettings()
            demo.savedReasons = [StopReasons.shorten("Phone call from family"), StopReasons.shorten("Had to pick up my brother from school")]
            save("stop-reason-\(suffix)", StopReasonCard(settings: demo, done: { _ in }, cancel: {}).frame(width: 280).environment(\.theme, t))
        }
    }

    /// Default layout matches the reference image: Today on the left, Focus and Garden stacked on the right.
    private func showPanels(force: Bool = false) {
        let themeKey = settings.themeMode + (theme.isNight ? "n" : "d")
        if force || themeKey != appliedTheme {
            panels.resetAll()
            appliedTheme = themeKey
        }
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let t = theme
        if settings.showToday {
            panels.show("today", size: CGSize(width: 560, height: 690), origin: CGPoint(x: screen.minX + 260, y: screen.maxY - 760), floating: settings.floatPanels) {
                TodayView().environmentObject(model).environment(\.theme, t)
            }
        } else { panels.hide("today") }
        if settings.showFocus {
            panels.show("focus", size: CGSize(width: 300, height: 230), origin: CGPoint(x: screen.maxX - 340, y: screen.maxY - 520), floating: settings.floatPanels) {
                FocusView().environmentObject(model).environment(\.theme, t)
            }
        } else { panels.hide("focus") }
        if settings.showProgress {
            panels.show("progress", size: CGSize(width: 380, height: 280), origin: CGPoint(x: screen.maxX - 420, y: screen.maxY - 330), floating: settings.floatPanels) {
                ProgressPanelView().environmentObject(model).environment(\.theme, t)
            }
        } else { panels.hide("progress") }
        panels.setFloating(settings.floatPanels)
    }
}
