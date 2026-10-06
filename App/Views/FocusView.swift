import PastelFocusCore
import SwiftUI

struct FocusView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.theme) var theme
    @Environment(\.snapshotMode) var snapshot
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var hover = false
    @State private var askingReason = false
    @State private var breathe = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SpriteView(rows: Sprite.target, px: 2)
                Text("Focus").font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.pink)
                Spacer()
                if snapshot { Image(systemName: "ellipsis").foregroundStyle(theme.textSecondary) } else { menu }
            }
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(clock).font(.system(size: 36, weight: .medium, design: .monospaced)).monospacedDigit()
                        .foregroundStyle(theme.isNight ? theme.pinkLight : theme.textPrimary)
                        .contentTransition(.numericText())
                    Text(label).font(.system(size: 13)).foregroundStyle(theme.textSecondary).lineLimit(1)
                }
                Spacer()
                if model.phase == .running || model.phase == .paused || model.phase == .resting, hover {
                    Button { askingReason = model.phase != .resting; if model.phase == .resting { model.stop(reason: nil) } } label: {
                        Image(systemName: "stop.fill").font(.system(size: 13)).foregroundStyle(theme.textSecondary).frame(width: 30, height: 30)
                            .background(Circle().fill(theme.elevated))
                    }.buttonStyle(.plain).help("Stop (⌥⌘.)")
                }
                playButton
            }
            HStack(spacing: 8) {
                Spacer()
                ForEach(0..<4) { i in Circle().fill(i == model.cycleIndex ? theme.pink : theme.track).frame(width: 7, height: 7) }
                Spacer()
            }
            gardenRow
        }
        .padding(20)
        .frame(width: 280, height: 210)
        .background(GlassBackground(radius: 18))
        .onHover { hover = $0 }
        .overlay { cards }
        .sheet(isPresented: $askingReason) { StopReasonSheet { reason in askingReason = false; model.stop(reason: reason) } cancel: { askingReason = false } }
    }

    private var clock: String {
        let s = model.phase == .idle ? model.plannedS : model.remainingS
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    private var label: String {
        switch model.phase {
        case .idle:
            if let r = model.lastEnded, Date().timeIntervalSince(r.endedAt) < 120 {
                return r.outcome == .completed ? "Focus complete ✦" : "Stopped early"
            }
            return model.selectedTask?.title ?? "Pick a task"
        case .running: return model.activeTitle ?? "Unassigned"
        case .paused: return "Paused"
        case .resting: return model.activeKind == .nsdr ? "NSDR" : model.activeKind == .longBreak ? "Long rest" : "Short rest"
        }
    }

    private var playButton: some View {
        Button {
            switch model.phase {
            case .idle: model.startFocus()
            case .running: model.pause()
            case .paused: model.resume()
            case .resting: model.pause()
            }
        } label: {
            Image(systemName: model.phase == .running || model.phase == .resting ? "pause.fill" : "play.fill")
                .font(.system(size: 20, weight: .bold)).foregroundStyle(Color(hex: 0x242234))
                .frame(width: 52, height: 52)
                .background(Circle().fill(theme.pinkStrong))
                .background(Circle().fill(theme.pinkStrong.opacity(breathe ? 0.20 : 0.10)).blur(radius: 9).scaleEffect(1.25))
        }
        .buttonStyle(PressableStyle())
        .help("Start or pause (⌥⌘F)")
        .onChange(of: model.phase) { _, p in
            guard !reduceMotion else { breathe = false; return }
            withAnimation(p == .running ? .easeInOut(duration: 2).repeatForever(autoreverses: true) : .default) { breathe = p == .running }
        }
    }

    private var menu: some View {
        Menu {
            Section("Task") {
                ForEach(model.openTasks) { t in
                    Button { model.selectedTaskID = t.taskID } label: {
                        Label(t.title, systemImage: t.taskID == model.selectedTaskID ? "checkmark" : "circle")
                    }
                }
                Button("No task (Unassigned)") { model.selectedTaskID = nil }
            }
            Section("Preset") {
                Picker("Preset", selection: Binding(get: { model.settings.presetName }, set: { model.settings.presetName = $0 })) {
                    Text("25 / 5").tag("25/5"); Text("50 / 10").tag("50/10"); Text("Custom").tag("custom")
                }
            }
            Section("Breaks") {
                Button("Short rest") { model.startRest(kind: .shortBreak) }
                Button("Long rest") { model.startRest(kind: .longBreak) }
                Button("NSDR, 15 min") { model.startRest(kind: .nsdr, minutes: 15) }
            }.disabled(model.phase != .idle)
        } label: { Image(systemName: "ellipsis").foregroundStyle(theme.textSecondary) }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 24)
    }

    /// Today's sessions as a row of tiny plants (grown or wilted).
    private var gardenRow: some View {
        HStack(spacing: 2) {
            ForEach(model.sessionsToday.filter { $0.kind == .focus }.suffix(14)) { s in
                SpriteView(rows: s.outcome == .completed ? Sprite.forCategory(s.category) : Sprite.wilted, px: 1.5)
            }
            Spacer()
        }
        .frame(height: 12)
    }

    @ViewBuilder private var cards: some View {
        if let s = model.suggestion {
            SuggestionCard(title: s.title, why: s.why, accept: actionTitle(s.action)) { model.answer(.accepted) } notNow: { model.answer(.dismissed) } mute: { model.answer(.muted) }
        } else if let (task, minutes, why) = model.hermesCard {
            SuggestionCard(title: "Hermes suggests \(minutes) min on \"\(task.title)\"", why: why ?? "Suggested by Hermes.", accept: "Start") {
                model.hermesCard = nil
                model.startFocus(on: task, minutes: minutes, skipSuggestion: true)
            } notNow: { model.hermesCard = nil } mute: { model.hermesCard = nil }
        }
    }

    private func actionTitle(_ a: SuggestionAction) -> String {
        switch a {
        case .useShorterSessions(let m): return "Use \(m) min"
        case .takeBreak(let k, let m): return k == .nsdr ? "Start NSDR (\(m) min)" : "Start \(m)-min break"
        case .raiseEstimate(_, let n): return "Plan \(n)"
        case .splitOrDrop: return "Open in Obsidian"
        }
    }
}

struct SuggestionCard: View {
    @Environment(\.theme) var theme
    let title: String
    let why: String
    let accept: String
    let onAccept: () -> Void
    let notNow: () -> Void
    let mute: () -> Void
    @State private var showWhy = false

    init(title: String, why: String, accept: String, onAccept: @escaping () -> Void, notNow: @escaping () -> Void, mute: @escaping () -> Void) {
        self.title = title; self.why = why; self.accept = accept; self.onAccept = onAccept; self.notNow = notNow; self.mute = mute
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
            if showWhy { Text(why).font(.system(size: 11)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true) }
            HStack(spacing: 10) {
                Button(accept, action: onAccept).buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.onPink)
                    .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(theme.pink))
                Button(showWhy ? "Hide" : "Why?") { showWhy.toggle() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(theme.pink)
                Button("Not now", action: notNow).buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(theme.textSecondary)
                Spacer()
                Menu { Button("Don't suggest this", action: mute) } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 18)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(theme.elevated))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.borderActive))
        .padding(8)
    }
}

struct StopReasonSheet: View {
    let done: (String?) -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stop early?").font(.headline)
            Text("It's logged as stopped early. Optional reason:").font(.subheadline).foregroundStyle(.secondary)
            HStack {
                ForEach(["interrupted", "blocked", "done early"], id: \.self) { r in Button(r) { done(r) } }
                Button("No reason") { done(nil) }
            }
            Button("Keep going", action: cancel).keyboardShortcut(.cancelAction)
        }
        .padding(20)
    }
}

struct ProgressPanelView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.theme) var theme
    @Environment(\.snapshotMode) var snapshot
    @State private var month = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SpriteView(rows: Sprite.sparkle, px: 2)
                Text("Night Garden").font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.pink)
                Spacer()
                if snapshot { Text("Week · Month").font(.system(size: 11)).foregroundStyle(theme.textSecondary) }
                else { Picker("", selection: $month) { Text("Week").tag(false); Text("Month").tag(true) }.pickerStyle(.segmented).frame(width: 130) }
            }
            if month {
                let islands = Array(model.garden.islands.suffix(5))
                HStack(spacing: 6) {
                    ForEach(islands, id: \.week) { IslandView(island: $0, landmarks: model.garden.landmarks, cell: 6, animate: false) }
                }
                .frame(maxWidth: .infinity)
            } else {
                IslandView(island: model.garden.islands.last { $0.week == currentWeek }, landmarks: model.garden.landmarks, cell: 26)
                    .frame(maxWidth: .infinity)
            }
            HStack {
                PixelLabel(text: "\(model.garden.goodDays) good days · run \(model.garden.currentRun)", size: 12)
                Spacer()
                if let next = Landmark.allCases.first(where: { !model.garden.landmarks.contains($0) }) {
                    Text("next: \(name(next)) at \(next.goodDays)").font(.system(size: 11)).foregroundStyle(theme.textSecondary)
                }
                Button { model.savePostcard() } label: { Image(systemName: "square.and.arrow.down") }
                    .buttonStyle(.plain).foregroundStyle(theme.textSecondary).help("Save this month as a postcard in the vault")
            }
        }
        .padding(20)
        .frame(width: 380, height: 280)
        .background(GlassBackground(radius: 18))
    }

    private var currentWeek: String { model.coordinator.calendar.isoWeek(Date()) }

    private func name(_ l: Landmark) -> String {
        switch l {
        case .path: return "path"
        case .pond: return "pond"
        case .stoneLantern: return "stone lantern"
        case .redBridge: return "red bridge"
        case .smallHouse: return "small house"
        case .waterfall: return "waterfall"
        }
    }
}
