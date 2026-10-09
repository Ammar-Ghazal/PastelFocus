import PastelFocusCore
import SwiftUI

struct FocusView: View {
    @EnvironmentObject var model: AppModel
    /// Per-second values; observed here (and by the menu bar) only.
    @EnvironmentObject var ticks: TickState
    @Environment(\.theme) var theme
    @Environment(\.snapshotMode) var snapshot
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var hover = false
    @State private var askingReason = false
    @State private var breathe = false
    @State private var picking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PanelTitle("Focus")
                Spacer()
                modeToggle
                if snapshot { Image(systemName: "ellipsis").foregroundStyle(theme.textSecondary) } else { menu }
            }
            HStack(alignment: .center, spacing: 18) {
                TimerDial(minutes: model.settings.focusMinutes, progress: dialProgress, clock: clock,
                          caption: dialCaption, onCommit: { model.setFocusMinutes($0) }, editable: !stopwatch)
                VStack(alignment: .leading, spacing: 10) {
                    TaskPickerButton(title: label, open: picking, enabled: canPick) { if !snapshot { setPicking(!picking) } }
                    HStack(spacing: 10) {
                        playButton
                        if model.phase != .idle {
                            Button {
                                if model.phase == .resting || model.isStopwatch { model.stop(reason: nil) }
                                else { withAnimation(.easeOut(duration: 0.15)) { askingReason = true } }
                            } label: {
                                Image(systemName: "stop.fill").font(.system(size: 12)).foregroundStyle(theme.textSecondary)
                                    .frame(width: 32, height: 32).background(Circle().fill(theme.elevated))
                            }
                            .buttonStyle(PressableStyle()).help("Stop (⌥⌘.)")
                            .transition(.opacity)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(PanelStyle.padding)
        // Top-aligned: centring in the fixed height left a bigger gap above the title than the other panels.
        .frame(width: 300, height: 200, alignment: .topLeading)
        .background(GlassBackground(radius: 18))
        .onHover { hover = $0 }
        .overlay(alignment: .top) { picker }
        .overlay { cards }
        .onChange(of: canPick) { _, can in if !can { setPicking(false) } }
    }

    /// The task can be chosen while idle or during a focus session, not during a rest.
    private var canPick: Bool { model.phase == .idle || model.focusInSession }

    private func setPicking(_ on: Bool) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.82)) { picking = on }
    }

    @ViewBuilder private var picker: some View {
        if picking {
            ZStack(alignment: .top) {
                // Clicking anywhere else closes it.
                Color.black.opacity(0.001).onTapGesture { setPicking(false) }
                TaskPickerList { setPicking(false) }
                    .padding(.horizontal, 10).padding(.top, 44)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.92, anchor: .top).combined(with: .opacity).combined(with: .offset(y: -6)))
            }
        }
    }

    /// Stopwatch look: idle in stopwatch mode, or a running stopwatch session.
    private var stopwatch: Bool { model.phase == .idle ? model.settings.stopwatchMode : model.isStopwatch }

    private var clock: String {
        if stopwatch {
            let s = model.phase == .idle ? 0 : ticks.elapsedS
            return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
        }
        let s = model.phase == .idle ? model.plannedS : ticks.remainingS
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// Ring fill while something runs: time left for a countdown, the current hour for a stopwatch.
    /// Nil while idle in timer mode (the dial is editable).
    private var dialProgress: Double? {
        if stopwatch { return model.phase == .idle ? 0 : Double(ticks.elapsedS % 3600) / 3600 }
        guard model.phase != .idle, model.plannedS > 0 else { return nil }
        return Double(ticks.remainingS) / Double(model.plannedS)
    }

    /// Two small pills; hidden while a session runs so the mode can't change mid-session.
    @ViewBuilder private var modeToggle: some View {
        if model.phase == .idle {
            HStack(spacing: 2) {
                ForEach([false, true], id: \.self) { sw in
                    let on = model.settings.stopwatchMode == sw
                    Button { model.settings.stopwatchMode = sw; model.objectWillChange.send() } label: {
                        Image(systemName: sw ? "stopwatch" : "timer")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(on ? theme.onAccent : theme.textSecondary)
                            .frame(width: 26, height: 20)
                            .background(Capsule().fill(on ? theme.accent : .clear))
                    }
                    .buttonStyle(.plain)
                    .help(sw ? "Stopwatch: count up, stop when you're done" : "Timer: count down from the dial")
                }
            }
            .padding(2)
            .background(Capsule().fill(theme.elevated))
        }
    }

    private var dialCaption: String {
        switch model.phase {
        case .idle: return stopwatch ? "stopwatch" : "min"
        case .running where stopwatch: return "elapsed"
        case .running: return "left"
        case .paused: return "paused"
        case .resting: return "rest"
        }
    }

    private var label: String {
        switch model.phase {
        case .idle:
            if let r = model.lastEnded, Date().timeIntervalSince(r.endedAt) < 120 {
                return r.outcome == .completed ? "Focus complete ✦" : "Stopped early"
            }
            return model.selectedTask?.title ?? "Pick a task"
        case .running: return model.activeTitle ?? "Unassigned"
        case .paused: return model.activeTitle ?? "Unassigned"
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
                .font(.system(size: 20, weight: .bold)).foregroundStyle(theme.onAccent)
                .frame(width: 52, height: 52)
                .background(Circle().fill(theme.accent))
                .background { if !snapshot { BreathingGlow(color: NSColor(theme.accent), active: breathe).frame(width: 80, height: 80) } }
        }
        .buttonStyle(PressableStyle())
        .help("Start or pause (⌥⌘F)")
        .onChange(of: model.phase, initial: true) { _, p in breathe = p == .running && !reduceMotion }
    }

    private var menu: some View {
        Menu {
            Section("Breaks") {
                Button("Short rest") { model.startRest(kind: .shortBreak) }
                Button("Long rest") { model.startRest(kind: .longBreak) }
                Button("NSDR, 15 min") { model.startRest(kind: .nsdr, minutes: 15) }
            }.disabled(model.phase != .idle)
        } label: { Image(systemName: "ellipsis").foregroundStyle(theme.textSecondary) }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 24)
    }

    @ViewBuilder private var cards: some View {
        if askingReason {
            StopReasonCard(settings: model.settings) { reason in
                askingReason = false
                model.stop(reason: reason)
            } cancel: { askingReason = false }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        } else if let s = model.suggestion {
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
                Button(accept, action: onAccept).buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.onAccent)
                    .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(theme.accent))
                Button(showWhy ? "Hide" : "Why?") { showWhy.toggle() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(theme.accent)
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

/// Inline "stop early?" card: quick reasons, saved custom reasons, or type one (optionally saved).
struct StopReasonCard: View {
    @Environment(\.theme) var theme
    @ObservedObject var settings: AppSettings
    let done: (String?) -> Void
    let cancel: () -> Void
    @State private var custom = ""
    @State private var save = false
    @FocusState private var typing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Stop early?").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.textPrimary)
                Spacer()
                Button("Keep going", action: cancel).buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(theme.accent)
                    .keyboardShortcut(.cancelAction)
            }
            FlowLayout(spacing: 5) {
                ForEach(StopReasons.builtIn + settings.savedReasons, id: \.self) { r in
                    Button { done(r) } label: { chip(r) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if settings.savedReasons.contains(r) {
                                Button("Remove saved reason") { settings.savedReasons.removeAll { $0 == r } }
                            }
                        }
                }
            }
            HStack(spacing: 6) {
                TextField("Other reason…", text: $custom)
                    .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(theme.track.opacity(0.6)))
                    .focused($typing)
                    .onSubmit(submit)
                Button(action: submit) { Image(systemName: "arrow.right.circle.fill").font(.system(size: 18)) }
                    .buttonStyle(.plain).foregroundStyle(custom.isEmpty ? theme.textTertiary : theme.accent).disabled(custom.isEmpty)
            }
            HStack {
                Toggle(isOn: $save) { Text("Save as a quick reason").font(.system(size: 11)).foregroundStyle(theme.textSecondary) }
                    .toggleStyle(.checkbox).disabled(custom.isEmpty)
                Spacer()
                Button("No reason") { done(nil) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(theme.textSecondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(theme.elevated))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.borderActive))
        .padding(6)
    }

    private func chip(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(theme.textPrimary).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(theme.track))
    }

    private func submit() {
        let text = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if save { settings.savedReasons = StopReasons.saving(text, to: settings.savedReasons) }
        done(text)
    }
}

/// Minimal wrapping row layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 260
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}

struct ProgressPanelView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.theme) var theme
    @Environment(\.snapshotMode) var snapshot
    @State private var period: GardenPeriod = .day
    /// Periods back from the current one (0 = today / this week / this month).
    @State private var offset = 0

    var body: some View {
        let cal = model.coordinator.calendar
        let day = period.shift(model.coordinator.today, by: -offset, calendar: cal)
        let plot = model.garden.plot(period, containing: day, calendar: cal)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PanelTitle("Night Garden")
                Spacer()
                if snapshot { Text("Day · Week · Month").font(.system(size: 11)).foregroundStyle(theme.textSecondary) }
                else {
                    Picker("", selection: $period) {
                        Text("Day").tag(GardenPeriod.day); Text("Week").tag(GardenPeriod.week); Text("Month").tag(GardenPeriod.month)
                    }
                    .pickerStyle(.segmented).frame(width: 170)
                    .onChange(of: period) { offset = 0 }
                }
            }
            HStack(spacing: 6) {
                stepButton("chevron.left", help: "Earlier") { offset += 1 }
                Text(title(day, cal)).font(.system(size: 12, weight: .medium)).foregroundStyle(theme.textSecondary)
                    .frame(minWidth: 110)
                stepButton("chevron.right", help: "Later") { offset -= 1 }.disabled(offset == 0).opacity(offset == 0 ? 0.3 : 1)
                Spacer()
                Text(count(plot)).font(.system(size: 11)).foregroundStyle(theme.textTertiary)
            }
            IsoPlotView(plot: plot).frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Text(progressText).font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.textPrimary).lineLimit(1)
                    .help("A good day is one with at least \(GoodDay.label(model.settings.goodDayMinutes)) of focused time (change it in Settings). Breaks don't count against it. The streak allows one missed day per week.")
                Spacer()
                if let next = Landmark.allCases.first(where: { !model.garden.landmarks.contains($0) }) {
                    let left = next.goodDays - model.garden.goodDays
                    Text("\(name(next).capitalized) unlocks in \(left) good day\(left == 1 ? "" : "s")").font(.system(size: 11)).foregroundStyle(theme.textSecondary)
                        .help("Good days unlock landmarks: path, pond, stone lantern, red bridge, small house, waterfall.")
                }
                Button { model.savePostcard(period, containing: day) } label: { Image(systemName: "square.and.arrow.down") }
                    .buttonStyle(.plain).foregroundStyle(theme.textSecondary).help("Save the garden you're viewing as a postcard in the vault")
            }
        }
        .padding(PanelStyle.padding)
        .frame(width: 380, height: 300, alignment: .topLeading)
        .background(GlassBackground(radius: 18))
    }

    private var progressText: String {
        let g = model.garden
        return "\(g.currentRun) day streak"
    }

    private func count(_ plot: GardenPlot) -> String {
        let n = plot.items.filter { $0.kind == .plant }.count
        return n == 0 ? "" : "\(n) plant\(n == 1 ? "" : "s")"
    }

    private func stepButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.textSecondary)
                .frame(width: 18, height: 18).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help)
    }

    /// "Today", "Wed 7 Oct", "5 – 11 Oct", "October 2026".
    private func title(_ day: String, _ cal: DayCalendar) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = cal.timeZone
        switch period {
        case .day:
            if offset == 0 { return "Today" }
            if offset == 1 { return "Yesterday" }
            f.dateFormat = "EEE d MMM"
            return cal.startOfDay(day).map(f.string) ?? day
        case .week:
            guard let d = cal.startOfDay(day), let start = cal.startOfDay(cal.weekStart(d)),
                  let end = cal.startOfDay(cal.addDays(6, to: cal.weekStart(d))) else { return day }
            f.dateFormat = "d"
            let a = f.string(from: start)
            f.dateFormat = "d MMM"
            return "\(a) – \(f.string(from: end))"
        case .month:
            f.dateFormat = "MMMM yyyy"
            return cal.startOfDay(day).map(f.string) ?? day
        }
    }

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


/// Soft pink halo that "breathes" while a session runs. Core Animation runs it in the render
/// server, so it costs the app nothing per frame (the SwiftUI version cost ~6% CPU).
struct BreathingGlow: NSViewRepresentable {
    let color: NSColor
    let active: Bool

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        let g = CAGradientLayer()
        g.type = .radial
        g.colors = [color.withAlphaComponent(0.55).cgColor, color.withAlphaComponent(0).cgColor]
        g.startPoint = CGPoint(x: 0.5, y: 0.5)
        g.endPoint = CGPoint(x: 1, y: 1)
        g.opacity = 0.18
        v.layer?.addSublayer(g)
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        guard let g = v.layer?.sublayers?.first as? CAGradientLayer else { return }
        g.frame = v.bounds
        if active, g.animation(forKey: "breathe") == nil {
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 0.18; a.toValue = 0.4
            a.duration = 2; a.autoreverses = true; a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            g.add(a, forKey: "breathe")
        } else if !active {
            g.removeAnimation(forKey: "breathe")
        }
    }
}
