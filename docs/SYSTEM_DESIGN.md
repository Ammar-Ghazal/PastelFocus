# PastelFocus system design

Working review, 2026-10-07. Product choices below are pending discussion with Ammar. Existing documentation and source comments describe the current project; they do not authorize new product behavior.

## How we will work

Ammar owns the experience, behavioral rules, constraints, and architectural trade-offs. AI explains alternatives, implements an agreed change, and supplies evidence that it meets those rules. Swift syntax can be delegated; the system's behavior and failure handling must remain explainable by its designer.

For each feature, keep a short record:

1. User scenario and observable outcome.
2. States, transitions, and failure cases.
3. Data owner and affected boundaries.
4. Chosen approach, alternative, and reason.
5. Acceptance checks and measured result.

Implement one coherent behavior at a time. Review both the diff and the running app. Keep tests that protect behavior rather than mirror implementation details.

## Current system

- Native macOS 14+ app: SwiftUI menu, three AppKit desktop panels, and settings and insights windows.
- Local `PastelFocusCore` package contains task parsing, timer state, session recording, reports, garden growth, and suggestions. There are no third-party runtime package dependencies; SQLite is supplied by the system.
- Markdown notes currently own task content. Monthly JSONL files hold sessions and task events. A private JSON snapshot restores the timer.
- Reports, garden state, and the SQLite index are derived from those inputs.
- FSEvents triggers debounced refreshes. The main-actor app model currently calls the coordinator synchronously for file operations and derived calculations.

Useful existing foundations: a timer engine with an injected clock, separate timer display updates, cached parsing of unchanged log files, write-if-changed guards, and core behavior tests. Preserve these unless a requirement calls for a different design.

## Findings to address

These are source-review findings, not measured performance results or reproduced failure reports.

| Finding | Practical consequence | Evidence |
| --- | --- | --- |
| Session recording errors are ignored before saving the new timer state. Recording also spans several files without deduplication by session ID. | A write failure can lose a session; a crash during partial completion can replay it. Agree on durable completion and recovery before refactoring. | `Coordinator.sessionEnded`, `SessionRecorder.record` |
| Development mode separates settings and support state but still defaults to the real Obsidian vault. Snapshot rendering initializes the normal model. | A preview or development run can change personal notes. Make a temporary fixture vault the default for both. | `AppSettings`, `AppDelegate.applicationDidFinishLaunching` |
| A one-second timer is scheduled while idle. Refresh and publication repeatedly scan tasks and derive history summaries and garden state on the main actor. | Avoidable wakeups and growing work as the vault grows. Measure before assigning numerical savings. | `AppModel.start/startTicker/publish`, `TaskStore.scan/stampMissingIDs`, `Coordinator.todayTotals/garden` |
| The SQLite index is rebuilt but production code does not call its query helpers. | Maintenance and writes without a current read benefit. Remove it if no agreed feature uses it; keep or redesign it only for a demonstrated need. | `IndexDatabase`, `Coordinator.nightly`, repository references |
| The ambient-motion preference does not govern every animated effect. | The setting does not fully express a quiet/static experience. Define one motion policy for visibility, preference, and Reduce Motion. | `PixelArt.AmbientLayer`, `FocusView.BreathingGlow`, `Theme.GlassBackground` |

Additional behavior decisions: handling simultaneous Obsidian edits, folder permission failures, sleep, long pauses, quit/relaunch, and suggestions that interrupt starting a session. Atomic file replacement alone does not establish safe coordination with another writer.

## Provisional architecture

For the current local-app scope, evolve the existing layered app rather than introduce another framework:

- **Presentation:** SwiftUI/AppKit reads view state and issues user commands.
- **Application commands:** one route for starting, pausing, resuming, stopping, and changing tasks, regardless of menu, shortcut, or Hermes input. Each route applies the same persistence and notification rules.
- **Domain:** retain deterministic timer, task, and garden rules that can be tested without launching macOS UI.
- **Storage and OS adapters:** one serialized owner for mutable state and file work, with explicit outcomes; keep expensive file/history work off the main actor. Notifications, login items, and folder access remain small adapters.
- **Derived views:** cache summaries and garden state by their actual inputs. Rebuild projections after relevant changes, rather than on every publication.

The authoritative storage choice remains open. Obsidian as the task authority requires an external-edit/conflict policy. An app-owned task store with Obsidian export is a different product and should not be introduced implicitly.

Add an abstraction only when it protects a boundary, makes an important behavior testable, or removes meaningful duplication. Lean code includes the small amount of recovery logic necessary to protect user data.

## Discussion sequence

| Round | Decisions we will make | Small output |
| --- | --- | --- |
| 1. Purpose and scope | Primary user outcome, essential first-version features, menu/panel/window model | Product brief and explicit deferred features |
| 2. Look and feel | Density, visual style, motion, keyboard interaction, interruption level, accessibility | One agreed primary screen and interaction rules |
| 3. Behavior | Complete task-to-focus journey; pause, sleep, rest, stop, completion, and restart | State diagram and acceptance scenarios |
| 4. Data and architecture | Obsidian ownership, offline behavior, failures, recovery, module boundaries | Architecture diagram and brief decision record |
| 5. Performance and implementation | Representative vault size, responsiveness/energy targets, prioritized fixes | Baseline measurements and one small implementation slice |
| 6. Delivery | CI, personal trials, beta criteria, sandbox/folder access, App Store readiness and versioning | Release checklist tied to evidence |

The first three questions are pending: primary purpose, normal presentation, and three essential features versus features that can wait. Later rounds depend on these answers.

## Performance approach

Start with measurements of idle/hidden, idle/visible with motion on and off, active focus, external note edits, and a large synthetic vault. Record CPU, wakeups, memory, launch time, refresh latency, and UI responsiveness. Include graphics/WindowServer cost when assessing animated panels.

Likely first candidates: stop the display ticker while idle; replace periodic full work with events and necessary deadlines; retain changed file paths and cache unaffected task parses; compute a day's totals and garden once per relevant revision; suspend decorative animation when hidden; remove an unused index if scope confirms it is unnecessary.

Do not promise zero CPU, instantaneous updates, or arbitrary numerical targets before profiling on a stated machine and dataset. Apple's guidance supports reducing timers, unnecessary work, and main-thread blocking: [Mac energy efficiency](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/BestPractices.html), [app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness), and [SwiftUI performance](https://developer.apple.com/documentation/Xcode/understanding-and-improving-swiftui-performance).

## Verification and release

The previous workflow review ran the core suite successfully: 86 tests. This design review has not changed app code, launched the app, profiled it, or verified a signed release build. Core tests do not cover every app/OS integration.

Once behavior is agreed, prioritize checks for failed session writes, interrupted completion/replay, external-edit conflicts, equivalent commands across controls, and recovery after restart. Use a temporary vault for manual validation. Establish a clean build and CI gate before accepting implementation slices.

The current main-app entitlements lack App Sandbox, so an App Store release needs a deliberate sandbox and user-selected folder-access design. Verify current distribution requirements when implementing that release gate. The existing [development workflow](DEVELOPMENT_WORKFLOW.md) remains the broader build/test/release reference.
