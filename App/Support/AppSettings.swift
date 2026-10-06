import Foundation
import PastelFocusCore

/// User settings in UserDefaults. Defaults follow the spec's section 9 recommendations.
final class AppSettings: ObservableObject {
    private let d = UserDefaults.standard

    @Published var vaultPath: String { didSet { d.set(vaultPath, forKey: "vaultPath") } }
    @Published var dailyFolder: String { didSet { d.set(dailyFolder, forKey: "dailyFolder") } }
    /// Raw session/event logs inside the vault (Hermes can read them) or private.
    @Published var logsInVault: Bool { didSet { d.set(logsInVault, forKey: "logsInVault") } }
    /// Off by default: Hermes may suggest sessions but not start them.
    @Published var allowHermesStart: Bool { didSet { d.set(allowHermesStart, forKey: "allowHermesStart") } }
    /// Panels sit at desktop level (behind windows) unless this is on.
    @Published var floatPanels: Bool { didSet { d.set(floatPanels, forKey: "floatPanels") } }
    /// Focus length chosen on the dial (5–120 min). Rest scales with it.
    @Published var focusMinutes: Int { didSet { d.set(focusMinutes, forKey: "focusMinutes") } }
    /// "night", "day" or "system".
    @Published var themeMode: String { didSet { d.set(themeMode, forKey: "themeMode") } }
    /// File path or URL opened when an NSDR break starts. Empty = none.
    @Published var nsdrAudio: String { didSet { d.set(nsdrAudio, forKey: "nsdrAudio") } }
    @Published var launchAtLogin: Bool { didSet { d.set(launchAtLogin, forKey: "launchAtLogin") } }
    @Published var showToday: Bool { didSet { d.set(showToday, forKey: "showToday") } }
    @Published var showFocus: Bool { didSet { d.set(showFocus, forKey: "showFocus") } }
    @Published var showProgress: Bool { didSet { d.set(showProgress, forKey: "showProgress") } }
    /// Stopwatch (count up, no end) instead of a countdown.
    @Published var stopwatchMode: Bool { didSet { d.set(stopwatchMode, forKey: "stopwatchMode") } }
    /// Custom stop-early reasons the user chose to keep (already shortened).
    @Published var savedReasons: [String] { didSet { d.set(savedReasons, forKey: "savedReasons") } }

    init() {
        d.register(defaults: [
            "vaultPath": FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Obsidian Vault").path,
            "dailyFolder": "Learning Library/Career/Daily Plans",
            "logsInVault": true, "allowHermesStart": false, "floatPanels": false,
            "focusMinutes": 25, "themeMode": "night",
            "nsdrAudio": "", "launchAtLogin": true, "showToday": true, "showFocus": true, "showProgress": true,
        ])
        vaultPath = d.string(forKey: "vaultPath")!
        dailyFolder = d.string(forKey: "dailyFolder")!
        logsInVault = d.bool(forKey: "logsInVault")
        allowHermesStart = d.bool(forKey: "allowHermesStart")
        floatPanels = d.bool(forKey: "floatPanels")
        // Migrate the old fixed presets.
        switch d.string(forKey: "presetName") {
        case "50/10": d.set(50, forKey: "focusMinutes")
        case "custom": d.set(DialMath.clamp(d.integer(forKey: "customFocus")), forKey: "focusMinutes")
        default: break
        }
        d.removeObject(forKey: "presetName")
        focusMinutes = DialMath.clamp(d.integer(forKey: "focusMinutes"))
        themeMode = d.string(forKey: "themeMode")!
        nsdrAudio = d.string(forKey: "nsdrAudio")!
        launchAtLogin = d.bool(forKey: "launchAtLogin")
        showToday = d.bool(forKey: "showToday")
        showFocus = d.bool(forKey: "showFocus")
        showProgress = d.bool(forKey: "showProgress")
        savedReasons = d.stringArray(forKey: "savedReasons") ?? []
        stopwatchMode = d.bool(forKey: "stopwatchMode")
    }

    var preset: FocusPreset { .forFocus(focusMinutes) }

    var vaultConfig: VaultConfig {
        VaultConfig(root: URL(fileURLWithPath: vaultPath, isDirectory: true), dailyFolder: dailyFolder, logsInVault: logsInVault)
    }
}
