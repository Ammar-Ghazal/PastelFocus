import Charts
import PastelFocusCore
import SwiftUI

struct InsightsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.theme) var theme

    struct DayBar: Identifiable { let id: String; let minutes: Int }
    struct BlockRate: Identifiable { let id: String; let rate: Double; let n: Int }

    var body: some View {
        let c = model.coordinator
        let sessions = c.recorder.log.readAll().filter { $0.kind == .focus }
        let days = (0..<14).reversed().map { c.calendar.addDays(-$0, to: c.today) }
        let bars = days.map { d in DayBar(id: String(d.suffix(5)), minutes: sessions.filter { c.calendar.day($0.startedAt) == d }.reduce(0) { $0 + $1.focusedS } / 60) }
        let blocks = stride(from: 6, to: 24, by: 2).compactMap { h -> BlockRate? in
            let inBlock = sessions.filter { c.calendar.hour($0.startedAt) / 2 * 2 == h }
            guard !inBlock.isEmpty else { return nil }
            return BlockRate(id: "\(h):00", rate: Double(inBlock.filter { $0.outcome.isInterrupted }.count) / Double(inBlock.count), n: inBlock.count)
        }

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Insights").font(.system(size: 26, weight: .bold)).foregroundStyle(theme.pink)
                if model.insights.isEmpty {
                    Text("Still learning: \(sessions.count) focus sessions so far. Most patterns need 2–4 weeks.")
                        .foregroundStyle(theme.textSecondary)
                }
                ForEach(model.insights, id: \.scope) { i in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(i.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.textPrimary)
                        Text(i.evidence).font(.system(size: 12)).foregroundStyle(theme.textSecondary)
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(theme.elevated))
                }
                Text("Focused minutes, last 14 days").font(.headline).foregroundStyle(theme.textPrimary)
                Chart(bars) { b in
                    BarMark(x: .value("Day", b.id), y: .value("Minutes", b.minutes)).foregroundStyle(theme.pink).cornerRadius(3)
                }
                .chartYAxisLabel("min").frame(height: 180)
                Text("Share of sessions interrupted, by start time").font(.headline).foregroundStyle(theme.textPrimary)
                if blocks.isEmpty {
                    Text("No sessions yet.").foregroundStyle(theme.textSecondary)
                } else {
                    Chart(blocks) { b in
                        BarMark(x: .value("Start", b.id), y: .value("Interrupted", b.rate)).foregroundStyle(theme.lavender).cornerRadius(3)
                            .annotation(position: .top) { Text("n=\(b.n)").font(.system(size: 9)).foregroundStyle(theme.textSecondary) }
                    }
                    .chartYScale(domain: 0...1)
                    .chartYAxis { AxisMarks(format: FloatingPointFormatStyle<Double>.Percent()) }
                    .frame(height: 180)
                }
                Button("Recompute now") { model.runNightly() }
            }
            .padding(24)
        }
        .frame(minWidth: 560, minHeight: 600)
        .background(Color(hex: 0x111827))
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section("Vault") {
                TextField("Vault folder", text: $settings.vaultPath)
                TextField("Daily notes folder (inside the vault)", text: $settings.dailyFolder)
                Toggle("Keep raw session logs in the vault (Hermes can read them)", isOn: $settings.logsInVault)
                Text("Off: raw logs stay in ~/Library/Application Support/PastelFocus/Logs and Hermes sees summaries only.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Hermes") {
                Toggle("Let Hermes start focus sessions directly", isOn: $settings.allowHermesStart)
                Text("Off: Hermes can only suggest a session; you accept or dismiss it.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Timer") {
                Stepper("Focus length \(settings.focusMinutes) min (also set on the dial)", value: $settings.focusMinutes, in: DialMath.minMinutes...DialMath.maxMinutes, step: DialMath.step)
                Text("Rest is about a fifth of that (\(settings.preset.shortRestMinutes) min; long rest \(settings.preset.longRestMinutes) min).")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("NSDR audio (file path or link)", text: $settings.nsdrAudio)
            }
            Section("Panels") {
                Toggle("Float panels above other windows", isOn: $settings.floatPanels)
                Toggle("Today", isOn: $settings.showToday)
                Toggle("Focus", isOn: $settings.showFocus)
                Toggle("Night Garden", isOn: $settings.showProgress)
                Picker("Theme", selection: $settings.themeMode) {
                    Text("Night").tag("night"); Text("Day").tag("day"); Text("Follow system").tag("system")
                }
                Toggle("Open at login", isOn: $settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 620)
    }
}

struct MenuBarContent: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) var openWindow
    @Environment(\.openSettings) var openSettings

    var body: some View {
        switch model.phase {
        case .idle: Button(model.settings.stopwatchMode ? "Start stopwatch  ⌥⌘F" : "Start focus  ⌥⌘F") { model.startFocus() }
        case .running: Button("Pause  ⌥⌘F") { model.pause() }; Button("Stop") { model.stop(reason: nil) }
        case .paused: Button("Resume  ⌥⌘F") { model.resume() }; Button("Stop") { model.stop(reason: nil) }
        case .resting: Button("Skip rest") { model.stop(reason: nil) }
        }
        Button("Start NSDR (15 min)") { model.startRest(kind: .nsdr, minutes: 15) }.disabled(model.phase != .idle)
        Divider()
        Text("\(model.tasks.filter { $0.status == .done }.count) of \(model.tasks.count) tasks · \(model.todayFocusedMin) min focused")
        Button("Insights…") { openWindow(id: "insights"); NSApp.activate() }
        Button("Save garden postcard") { model.savePostcard() }
        Button("Open vault folder") { NSWorkspace.shared.open(model.coordinator.config.appDir) }
        Button("Refresh now") { model.refreshNow() }
        Divider()
        Button("Settings…") { openSettings(); NSApp.activate() }.keyboardShortcut(",")
        Button("Quit PastelFocus") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

/// Menu-bar label: sprout plus time left while a session runs.
struct MenuBarLabel: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var ticks: TickState
    var body: some View {
        switch model.phase {
        case .idle: Image(systemName: "leaf")
        case .running, .paused, .resting:
            let s = model.isStopwatch ? ticks.elapsedS : ticks.remainingS
            HStack(spacing: 3) {
                Image(systemName: model.phase == .resting ? "cup.and.saucer" : "leaf.fill")
                Text(s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)).monospacedDigit()
            }
            .opacity(model.phase == .paused ? 0.5 : 1)
        }
    }
}
