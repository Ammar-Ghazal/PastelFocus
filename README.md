# PastelFocus

A local-first macOS app with three pastel desktop panels — **Today** (tasks), **Focus** (Pomodoro/Forest-style timer) and **Night Garden** (progress) — that shares everything with the Hermes agent through the Obsidian vault. No server, no cloud, no paid dependencies.

Specs: [Feasibility and Architecture](https://claude.ai/code/artifact/ad2232a3-d8ee-4438-93d8-57e2d7ddb60d) · [Visual design](https://claude.ai/code/artifact/272891d3-76e0-4dc8-9a34-2c92d15eb115)

## Architecture

```
┌──────────────── PastelFocus.app (menu-bar app, always running) ────────────────┐
│  Desktop panels (NSPanel + SwiftUI)   Today · Focus · Night Garden            │
│  Menu bar, ⌥⌘F / ⌥⌘. hot keys, notifications, Insights window, Settings       │
│                 │ AppModel (main thread)                                       │
│                 ▼                                                              │
│  PastelFocusCore (Swift package, no UI, fully unit-tested)                     │
│   Coordinator ─ TaskStore ─ InboxProcessor ─ FocusEngine ─ SessionRecorder     │
│               ─ AnalyticsEngine ─ SuggestionEngine ─ GardenBuilder ─ Reports   │
│               ─ IndexDatabase (private SQLite cache) ─ WidgetBridge            │
└───────┬──────────────────────────────────────────────────┬────────────────────┘
        │ FSEvents watch + safe line edits                  │ snapshot.json / widget-commands.jsonl
        ▼                                                   ▼
  Obsidian vault (source of truth)                    App Group container
  ├─ Learning Library/Career/Daily Plans/*.md          └─ WidgetKit extension (Today, Focus, Progress)
  └─ PastelFocus/ Inbox.md Now.md Insights.md
                  Backlog.md Problems.md Stats/ Logs/ Garden/
        ▲
        │ file tools (obsidian skill)
  Hermes gateway: 8am plan · 9:10pm Focus Review · Sunday weekly plan
```

**The vault is the only interface between the app and Hermes.** The app watches the vault, applies changes within ~1 s, and writes summaries back. The SQLite index in `~/Library/Application Support/PastelFocus/index.sqlite` is a cache rebuilt from the vault; delete it any time (while the app is quit).

### What runs when

| Component | Runs |
| --- | --- |
| PastelFocus.app | Always (login item). 0% CPU idle, ~2% while a session runs, ~40 MB memory |
| Inbox processing, outside-edit detection | Within ~1 s of a file change (FSEvents) |
| Timer tick | Every second while a session runs; time is computed from the clock, so sleep/App Nap/restarts are safe |
| Nightly pass (insights, Stats, daily summary, index) | First wake after midnight and 21:00 |
| Garden animation | Core Animation layers (render server), no per-frame app work |
| Widgets | Drawn by macOS from the snapshot the app writes |

## Vault files

| Path | Written by | Purpose |
| --- | --- | --- |
| `Learning Library/Career/Daily Plans/YYYY-MM-DD.md` | Hermes, you, app | Task lines, `## Focus log`, `## PastelFocus summary` |
| `PastelFocus/Backlog.md` | you, Hermes, app | Tasks not tied to a day |
| `PastelFocus/Inbox.md` | Hermes, you | Commands the app applies and ticks with a result |
| `PastelFocus/Now.md` | app | Running timer, today's totals, open tasks with IDs |
| `PastelFocus/Insights.md` | app (nightly) | Patterns with evidence, or "Still learning" |
| `PastelFocus/Stats/YYYY-Www.md`, `YYYY-MM.md` | app (nightly) | Weekly / monthly summaries |
| `PastelFocus/Logs/{sessions,events,suggestions}-YYYY-MM.jsonl` | app | Append-only raw history (or private, see Settings) |
| `PastelFocus/Problems.md` | app | Lines it couldn't read (never deletes them) |
| `PastelFocus/Garden/YYYY-MM.png` | app | Monthly garden postcard |

### Task line (Obsidian Tasks plugin format)

```
- [ ] Finalize resume — one ready-to-send version #career [est:: 3] [sessions:: 1] ⏫ ➕ 2026-10-05 ⏳ 2026-10-07 📅 2026-10-10 🆔 r7q2
    - notes as indented sub-bullets
```

Legacy Hermes lines (`- [ ] **P1 · 90 min** Title — detail`) are still read: P1/P2/P3 → priority, minutes → estimated sessions.

### Inbox commands

`create <task line>` · `reschedule 🆔 id ⏳ YYYY-MM-DD` · `priority 🆔 id high|medium|low|none` · `estimate 🆔 id N` · `complete|reopen|cancel|later 🆔 id` · `suggest-focus 🆔 id 40m` · `start-focus 🆔 id 25m` (off unless allowed in Settings) · `link-session <session id> 🆔 id`. Append ` — reason: …`. Results: `→ applied HH:MM by hermes` or `→ error: …`, with an Undo toast in the app.

## Analytics and suggestions

Plain statistics in `AnalyticsEngine` (no model): focus span, interruption rates by category / time of day / block of the day (fatigue), weekdays, pause position, estimate ratios, repeated postponements, best time per category, NSDR effect. A pattern needs ≥12 sessions on ≥7 days, a ≥1.5× rate gap (or ≥20% duration gap) and non-overlapping 80% Wilson intervals.

`SuggestionEngine` turns insights into rare cards, only at a session start, a session end or planning — never mid-session: ≤3 per day, ≥90 min apart, each kind ≤ once per 3 days, paused 14 days after two dismissals, mutable. Every card has **Why?** with the real numbers.

## Focus panel

- **Timer dial:** drag the ring (or use the arrow keys) to set 5–120 min in 5-min steps; rest scales with it (about a fifth, 3–20 min; long rest ×3). While running, the ring shows time left.
- **Stopwatch mode:** the toggle in the header switches to counting up. Stopping a stopwatch finishes it (logged as completed, `preset: "stopwatch"`, planned = actual); a forgotten one stops itself after 4 h.
- **Stop early:** quick reasons (`interrupted`, `blocked`, `done early`), your saved reasons, or type your own and tick *Save as a quick reason*. Saved reasons are shortened to 22 characters at a word boundary; right-click one to remove it. The daily note shows the short label; the sessions log keeps your full text.

## Performance notes

- Per-second timer values live in `TickState`, observed only by the Focus panel and menu-bar label, so the Today list doesn't redraw every second.
- Looping animations (garden fireflies, play-button glow) are Core Animation layers that run in the render server; the dial ring eases only when you change it, not on every tick.
- Log files are cached per file and re-parsed only when their size or date changes; widgets reload only when their snapshot changes; generated files are written only when their content changes.

## Night Garden

Each finished focus session plants a pixel sprite (species by category, size by minutes, glowing if ≥40 min with no pauses, golden if the task had been postponed 3+ times). Stopped sessions leave a wilted sprout that becomes soil after a day; NSDR leaves a sleeping cat. Good days (≥2 finished sessions) unlock a path, pond, stone lantern, red bridge, small house and waterfall. Layout is deterministic (FNV-1a seed per session), so it never reshuffles.

## Build, test, install

```bash
swift test                      # 75 unit/integration tests for PastelFocusCore
./scripts/install.sh            # xcodegen + Release build → ~/Applications, relaunch
./build/Build/Products/Debug/PastelFocus.app/Contents/MacOS/PastelFocus --render-snapshots /tmp/pf   # PNGs of every panel, both themes
```

Run a separate copy for development or benchmarking without touching the installed app's timer or settings (own settings suite, temp support folder, no widgets, login item or hot keys):

```bash
PASTELFOCUS_DEV=bench ./build/Build/Products/Debug/PastelFocus.app/Contents/MacOS/PastelFocus
```

Requires Xcode 27, `xcodegen` (Homebrew) and the Apple Developer team `58FZ49BXRF` (signing + App Group `58FZ49BXRF.com.ammarghazal.pastelfocus` for widgets).

| Test file | Covers |
| --- | --- |
| `TaskLineParserTests` | Tasks-plugin fields, round-trip, legacy lines, IDs |
| `TaskStoreTests` | Scan, Today filter, ID stamping, edits + events, create, outside-edit diff, Problems.md, concurrent-write conflict |
| `FocusEngineTests` | Completion, pause/resume, stop, paused-out, sleep, cycle, restart restore, recorder output |
| `InboxTests` | Command parsing, apply + tick results, focus commands, header |
| `AnalyticsTests` | Wilson interval, thresholds, focus span, category, fatigue, estimates, postponed, reports |
| `SuggestionTests` | Each rule, never mid-session, budget, dismissals, mute |
| `GardenTests` | Growth rules, stable non-overlapping layout, landmarks/run, fireflies |
| `StopReasonsTests` | Shortening, saving, de-duplication, short label in the note |
| `DialMathTests` | Angle ↔ minutes, 5-min snapping, no wrap across 12, rest scaling |
| `StopwatchTests` | Count up, stop = completed, pauses, 4 h cap, old state loads, analytics |
| `LogCacheTests` | Cache hits, appends and outside edits invalidate |
| `CoordinatorTests` | End-to-end: refresh, no-op write guard, outside edits, Hermes Inbox, timer + restart, widget taps, nightly files, index rebuild |

## Settings (menu bar → Settings…)

Vault and daily-notes folder · raw logs in vault (on) or private · let Hermes start sessions (off) · focus length (also on the dial) · NSDR audio · float panels above windows (off = desktop level) · panel visibility · Night / Day / system theme · open at login.

## Code map

```
Sources/PastelFocusCore/   Model/ Vault/ Inbox/ Timer/ Analytics/ Suggestions/ Garden/ Index/ Widgets/ Coordinator.swift
App/                       PastelFocusApp.swift, AppModel.swift, Support/ (theme, settings, system services), Views/
Widgets/                   WidgetKit bundle + App Intents
Tests/PastelFocusCoreTests/
project.yml                XcodeGen project (app + widget extension)
```
