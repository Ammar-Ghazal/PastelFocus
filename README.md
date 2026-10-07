# PastelFocus

A local-first macOS app with three pastel desktop panels — **Today** (tasks), **Focus** (Pomodoro/Forest-style timer) and **Night Garden** (progress) — that shares everything with the Hermes agent through the Obsidian vault. No server, no cloud, no paid dependencies.

Development process: [Development and release workflow](docs/DEVELOPMENT_WORKFLOW.md) — testing, fixes, ChatGPT/Claude handoffs, and Mac App Store releases.

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
│               ─ IndexDatabase (private SQLite cache)                           │
└───────┬────────────────────────────────────────────────────────────────────────┘
        │ FSEvents watch + safe line edits
        ▼
  Obsidian vault (source of truth)
  ├─ Learning Library/Career/Daily Plans/*.md
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
| `PastelFocus/Garden/YYYY-MM.png` (or `YYYY-Www`, `YYYY-MM-DD`) | app | Garden postcard: each month automatically, any view on request |

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

## Themes

12 themes × 21 colour combos (252 palettes), chosen in **Settings → Appearance** (or the menu bar's Theme menu). Each theme is a scene with its own art, ambient motion and title typeface:

| Theme | Scene and motion | Type |
| --- | --- | --- |
| Pastel Retro | Dark glass, pixel sparkles (the original look) | SF |
| Deep Space | Twinkling stars, planets orbiting a glowing sun | SF |
| Enchanted Forest | Misty pines, drifting fireflies | Serif |
| Ocean Depths | Light rays, rising bubbles | Rounded |
| Synthwave | Striped neon sun, horizon grid | SF |
| Zen Paper | Paper grain, ink ensō, no motion | Serif |
| Cozy Autumn | Warm glow, falling leaves | Serif |
| Aurora | Swaying aurora ribbons over a ridge | SF |
| Desert Dusk | Dunes, low sun, blowing sand | SF |
| Sakura Garden | Blossom branch, drifting petals | Rounded |
| Retro Terminal | CRT scanlines, blinking cursor | Mono |
| Winter Snowfall | Snowfall over hills and pines | Rounded |

**How palettes are made (`Sources/PastelFocusCore/Theme`).** Each combo is a one-line spec — mode, background hue, accent hue, vibrance, tag hues. `PaletteBuilder` derives all 25 tokens in OKLCH (perceptual lightness/chroma, gamut-mapped to sRGB), then enforces WCAG contrast: primary text ≥ 7:1, secondary ≥ 4.5:1, tags ≥ 4.5:1, and text on accent fills ≥ 4.5:1 (dark or light text, whichever reads better). `ThemeTests` checks every palette for these, for in-gamut colours, unique IDs, and tag colours that stay distinguishable. The original Midnight Blossom palette is kept exactly.

**Where it renders.** `App/Theme/ThemeKit.swift` (tokens → SwiftUI) and `App/Theme/SceneArt.swift` (static scene art, drawn once with `Canvas`). On top of that the app adds `AmbientScene` — Core Animation layers and particle emitters (0% app CPU). *Ambient motion* and macOS Reduce Motion switch it off. *Match macOS light/dark* swaps to the theme's closest combo of the other mode.

## Performance notes

- Per-second timer values live in `TickState`, observed only by the Focus panel and menu-bar label, so the Today list doesn't redraw every second.
- Looping animations (garden fireflies, play-button glow) are Core Animation layers that run in the render server; the dial ring eases only when you change it, not on every tick.
- Log files are cached per file and re-parsed only when their size or date changes; generated files are written only when their content changes.

## Night Garden

Each finished focus session plants a pixel sprite (species by category, size by minutes, glowing if ≥40 min with no pauses, golden if the task had been postponed 3+ times). Stopped sessions leave a wilted sprout that becomes soil after a day; NSDR leaves a sleeping cat. Good days unlock a path, pond, stone lantern, red bridge, small house and waterfall; the streak counts good days in a row, allowing one missed day per week. A good day is total focused time across all focus sessions (finished or stopped) reaching a threshold you set in Settings, 3 h by default; breaks and NSDR neither count nor spoil it. Stats files show the same count.

Like Forest, the garden is an isometric block of land with **Day / Week / Month** views (arrows step back through earlier periods). The plot starts at 4×4 tiles and grows so it's never more than ~45% full; tiles shrink as it grows, so the view zooms out instead of getting cluttered. Each session has a fixed home (a fraction of the plot from an FNV-1a seed of its id) and takes the free tile nearest it, earliest sessions first, so plants stay within about a tile of their relative spot as the plot grows. The save button writes the period you're viewing to `PastelFocus/Garden/` (`2026-10.png`, `2026-W41.png` or `2026-10-07.png`); last month's is saved automatically. Fireflies (one per finished task) and the waterfall are Core Animation layers.

## Build, test, install

Xcode's window can stay closed: XcodeGen generates the project from `project.yml`, and `xcodebuild` builds the native macOS app using the installed Xcode tools. Full Xcode is required. See the [terminal development workflow](docs/DEVELOPMENT_WORKFLOW.md#4-the-daily-terminal-build-test-and-fix-loop) for setup, isolated launches, screenshots, and release archives.

```bash
swift test                      # unit/integration tests for PastelFocusCore; does not package the app
xcodegen generate
xcodebuild -project PastelFocus.xcodeproj -scheme PastelFocus -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build build
```

The existing `./scripts/install.sh` builds Release, installs to `~/Applications`, and relaunches. Its error handling needs correction before relying on it: a suppressed build failure can leave an older app available for installation.

`PASTELFOCUS_DEV=<name>` uses a separate settings suite and temporary support folder, and disables login registration and hot keys. It still defaults to the real vault and shares some state. Use the workflow's separate test account and fixture-vault setup before launching development copies or rendering snapshots.

Requires Xcode 27, `xcodegen` (Homebrew) and the Apple Developer team `58FZ49BXRF` for signing.

| Test file | Covers |
| --- | --- |
| `TaskLineParserTests` | Tasks-plugin fields, round-trip, legacy lines, IDs |
| `TaskStoreTests` | Scan, Today filter, ID stamping, edits + events, create, outside-edit diff, Problems.md, concurrent-write conflict |
| `FocusEngineTests` | Completion, pause/resume, stop, paused-out, sleep, cycle, restart restore, recorder output |
| `InboxTests` | Command parsing, apply + tick results, focus commands, header |
| `AnalyticsTests` | Wilson interval, thresholds, focus span, category, fatigue, estimates, postponed, reports |
| `SuggestionTests` | Each rule, never mid-session, budget, dismissals, mute |
| `GardenTests` | Growth rules, stable non-overlapping layout per period, plot grows with items, plants keep their relative spot as it grows, period keys/shifts, landmarks/run, fireflies |
| `StopReasonsTests` | Shortening, saving, de-duplication, short label in the note |
| `DialMathTests` | Angle ↔ minutes, 5-min snapping, no wrap across 12, rest scaling |
| `StopwatchTests` | Count up, stop = completed, pauses, 4 h cap, old state loads, analytics |
| `LogCacheTests` | Cache hits, appends and outside edits invalidate |
| `ThemeTests` | 12 themes × 21 palettes: contrast, gamut, unique IDs, distinguishable tags, light/dark matching |
| `CoordinatorTests` | End-to-end: refresh, no-op write guard, outside edits, Hermes Inbox, timer + restart, nightly files, index rebuild |
| `CareerCoachContractTests` | Link career-coach boundary: Inbox create/reschedule round-trip without duplicates, wiki/report checklists never become tasks; replays a real coach run (on a temp copy) when `PASTELFOCUS_COACH_FIXTURE` is set |

## Settings (menu bar → Settings…)

Vault and daily-notes folder · raw logs in vault (on) or private · let Hermes start sessions (off) · focus length (also on the dial) · good-day threshold (3 h) · NSDR audio · float panels above windows (off = desktop level) · panel visibility · open at login. Appearance tab: theme, colour combo, ambient motion, match macOS light/dark.

## Code map

```
Sources/PastelFocusCore/   Model/ Vault/ Inbox/ Timer/ Analytics/ Suggestions/ Garden/ Index/ Coordinator.swift
App/                       PastelFocusApp.swift, AppModel.swift, Support/ (panel styling, settings, system services), Theme/ (tokens, scene art), Views/
Tests/PastelFocusCoreTests/
project.yml                XcodeGen project
```
