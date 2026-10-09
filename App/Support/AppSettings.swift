import Foundation
import PastelFocusCore

/// User settings in UserDefaults. Defaults follow the spec's section 9 recommendations.
final class AppSettings: ObservableObject {
    /// Development only: `PASTELFOCUS_DEV=<name>` runs a fully separate instance (own settings suite,
    /// support folder, no login item or hot keys) so it can't disturb the installed app's timer or settings.
    static let devName = ProcessInfo.processInfo.environment["PASTELFOCUS_DEV"]
    private let d = devName.flatMap { UserDefaults(suiteName: "com.ammarghazal.pastelfocus.dev.\($0)") } ?? .standard

    var supportDir: URL {
        AppSettings.devName.map { FileManager.default.temporaryDirectory.appendingPathComponent("PastelFocus-dev-\($0)") }
            ?? VaultConfig.defaultSupportDirectory
    }

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
    /// Theme (scene) and colour combo.
    @Published var themeSelection: ThemeSelection {
        didSet { d.set(themeSelection.themeID, forKey: "themeID"); d.set(themeSelection.paletteID, forKey: "paletteID") }
    }
    /// Swap to the theme's closest light/dark palette to follow macOS appearance.
    @Published var matchSystemAppearance: Bool { didSet { d.set(matchSystemAppearance, forKey: "matchSystemAppearance") } }
    /// Animated scenes (stars, snow, petals…). Off = static art only; Reduce Motion also turns it off.
    @Published var ambientMotion: Bool { didSet { d.set(ambientMotion, forKey: "ambientMotion") } }
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
    /// Focused minutes in a day that make it a good day (Night Garden streak and landmarks).
    @Published var goodDayMinutes: Int { didSet { d.set(goodDayMinutes, forKey: "goodDayMinutes") } }
    /// How the Focus panel draws time (ring, clock, hourglass, water drip).
    @Published var timerStyle: TimerStyle { didSet { d.set(timerStyle.rawValue, forKey: "timerStyle") } }
    /// Order of the Today list.
    @Published var taskSort: TaskSort { didSet { d.set(taskSort.rawValue, forKey: "taskSort") } }

    init() {
        d.register(defaults: [
            "vaultPath": FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Obsidian Vault").path,
            "dailyFolder": "Learning Library/Career/Daily Plans",
            "logsInVault": true, "allowHermesStart": false, "floatPanels": false,
            "focusMinutes": 25, "goodDayMinutes": GoodDay.defaultMinutes, "matchSystemAppearance": false, "ambientMotion": true,
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
        goodDayMinutes = min(GoodDay.range.upperBound, max(GoodDay.range.lowerBound, d.integer(forKey: "goodDayMinutes")))
        // Migrate the old Night / Day / System choice.
        if let old = d.string(forKey: "themeMode") {
            let fallback = ThemeSelection.default
            d.set(fallback.themeID, forKey: "themeID")
            d.set(old == "day" ? "pastel-retro/morning-blossom" : fallback.paletteID, forKey: "paletteID")
            if old == "system" { d.set(true, forKey: "matchSystemAppearance") }
            d.removeObject(forKey: "themeMode")
        }
        themeSelection = ThemeSelection(themeID: d.string(forKey: "themeID") ?? ThemeSelection.default.themeID,
                                        paletteID: d.string(forKey: "paletteID") ?? ThemeSelection.default.paletteID)
        matchSystemAppearance = d.bool(forKey: "matchSystemAppearance")
        ambientMotion = d.bool(forKey: "ambientMotion")
        nsdrAudio = d.string(forKey: "nsdrAudio")!
        launchAtLogin = d.bool(forKey: "launchAtLogin")
        showToday = d.bool(forKey: "showToday")
        showFocus = d.bool(forKey: "showFocus")
        showProgress = d.bool(forKey: "showProgress")
        savedReasons = d.stringArray(forKey: "savedReasons") ?? []
        stopwatchMode = d.bool(forKey: "stopwatchMode")
        taskSort = d.string(forKey: "taskSort").flatMap(TaskSort.init(rawValue:)) ?? .time
        timerStyle = d.string(forKey: "timerStyle").flatMap(TimerStyle.init(rawValue:)) ?? .ring
    }

    var preset: FocusPreset { .forFocus(focusMinutes) }

    var vaultConfig: VaultConfig {
        VaultConfig(root: URL(fileURLWithPath: vaultPath, isDirectory: true), dailyFolder: dailyFolder, logsInVault: logsInVault)
    }
}
