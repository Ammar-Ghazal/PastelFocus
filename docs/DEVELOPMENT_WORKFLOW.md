# PastelFocus development and release workflow

Prepared on 7 October 2026 against local commit `bdfefc6`. This is a working playbook for Ammar, ChatGPT, and Claude. It describes the recommended process; CI, scripts, and release configuration proposed below still need implementation.

## 1. What a push changes

A GitHub push updates source code. A running Mac app uses the binary that was built and launched earlier.

| Change | How to see it |
| --- | --- |
| Swift source, bundled art, dependencies, or build configuration | Build the changed checkout, then launch the new app |
| Code written by a cloud assistant or on another computer | Bring that commit into your local checkout, then build and launch |
| Settings such as a theme | Usually immediate through the app's observed state |
| Tasks or Inbox commands in the vault | The running app watches supported folders and refreshes |
| SwiftUI view code in an Xcode preview | A configured preview can refresh as you edit |
| A build released to customers | Customers receive the approved update through the Mac App Store |

Restarting the existing installed app alone does not compile your changes. Pushing alone does not install them. You do not need to restart macOS.

During AI-assisted development, use the terminal build and launch process in section 4 after a coherent change. You can make several edits before running. Xcode's Stop and Run controls are an optional alternative. Previews help with layout, but the launched app is where you validate panels, menu commands, notifications, and lifecycle behavior. See [Apple's preview documentation](https://developer.apple.com/documentation/swiftui/previews-in-xcode).

`scripts/install.sh` currently generates the project, builds Release, replaces `~/Applications/PastelFocus.app`, and relaunches it. Treat installing your personal copy as a separate step after testing.

## 2. Current foundation and the first improvements

The project already separates `PastelFocusCore` from SwiftUI/AppKit, uses `MenuBarExtra` and `LSUIElement`, persists timer state, watches vault changes, and shares snapshots with WidgetKit. Preserve these boundaries.

On 7 October 2026, all **86 core unit/integration tests passed** using the installed Xcode 27.0 / Swift 6.4 toolchain. This run did not validate GUI behavior, a signed archive, or App Store acceptance. The package and app currently compile in Swift 5 language mode; a newer compiler does not mean Swift 6 strict concurrency is enabled.

Address these items before relying on the release process:

| Priority | Finding in this checkout | Concrete next task |
| --- | --- | --- |
| First | The install script suppresses build failure with `|| true`; an older build directory can still exist | Preserve the real build exit status, retain the previous installed app until success, and quit the intended instance gracefully before replacement |
| First | `PASTELFOCUS_DEV` separates some settings and support files, but the default vault is still the real vault | Require a fixture vault before model initialization; isolate every writable path and side effect |
| Before store beta | The main app lacks the sandbox entitlement; the widget has it | Enable and exercise the main app sandbox; implement user-selected folder access and persistent security-scoped bookmarks |
| Before store beta | Login-at-launch defaults to enabled and registration happens at startup | Make launch at login an explicit opt-in that applies immediately; reflect actual service status and registration errors |
| Before store beta | Vault paths and some product text are personal defaults | Add first-run setup, folder selection, neutral defaults, and a useful experience without Hermes or Obsidian installed |
| Before store beta | Version/build values are duplicated in project settings and both plists | Use one version source and keep app and widget version/build values aligned |
| Before public release | No GitHub Actions workflow or app UI-test target is tracked | Add the CI checks below and a few high-value UI smoke tests |
| Before public release | Store assets and privacy documentation need preparation | Add a proper app icon, product screenshots, support/privacy pages, and accurate privacy declarations |

Development isolation needs more than a settings suite. `AppModel.lastNightlyDay` uses standard defaults, notification setup is unconditional, and the default private-log directory can still point to production storage. A dedicated development bundle identifier, fixture vault, support directory, notification namespace, and optional development App Group should isolate those too. Development hot keys and login registration are already disabled.

Until that isolation is complete, use a separate macOS test account and a disposable vault for app-level testing. Do not treat `PASTELFOCUS_DEV` alone as protection for the real vault. The existing snapshot-rendering path initializes the model before rendering, so it needs the same precautions.

Apple requires Mac App Store apps to be sandboxed and prohibits automatic login launch without consent. See [App Review Guidelines, section 2.4.5](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility).

## 3. One shared process for ChatGPT and Claude

Use **one implementer and one reviewer for each change**. Either assistant can take either role; switch roles when useful. You own requirements, accept the behavior, and decide when to release.

1. **Write a small issue.** Include the observed problem, expected result, reproduction steps, app version/build, macOS version, and a screenshot or sample fixture when useful.
2. **Start from current main.** Keep a single integration branch, `main`, and use short branches such as `codex/timer-wake`. Do not maintain competing `main` and `master` integration histories.
3. **Give one assistant ownership of implementation.** Identify allowed scope, acceptance criteria, and required verification. Keep unrelated cleanup out of the fix.
4. **Have the other assistant review the final diff.** Give it the issue, base/head commits, and verification results. Ask it to identify concrete failure cases and check the implementation independently.
5. **Resolve valid findings and rerun affected checks.** A review is not evidence that unexecuted tests passed.
6. **Perform the short manual acceptance check yourself.** An app that builds can still have broken first-click behavior, drag hit areas, focus, or menu commands.
7. **Merge through a PR when the required checks pass.** Record the user-visible change and any remaining limitation.

If both assistants run locally at the same time, give them separate Git worktrees, branches, build directories, and development identities. They should not edit the same checkout concurrently. Keep this shared playbook in the repository so it travels with both local and cloud tasks.

As a small follow-up, add root `AGENTS.md` and `CLAUDE.md` files that point to this playbook and record these invariants: the vault is the source of truth; preserve unrelated Markdown; retain old-state compatibility; isolate test data; use public Apple APIs; report commands actually executed; keep signing credentials outside Git.

Reusable implementation prompt:

```text
Read README.md and docs/DEVELOPMENT_WORKFLOW.md.
Implement issue <number> on a short branch.
Expected behavior: <specific acceptance criteria>.
Reproduction: <steps and synthetic fixture>.
Make the smallest complete fix; keep unrelated changes separate.
Add a regression test when the behavior warrants one.
Run the applicable core tests and app build.
Use the terminal workflow in section 4; Xcode's window can stay closed.
Stop after any failed command and diagnose it before continuing.
Report the commit, commands/results, and exact built app path.
For UI work, capture useful images and list manual checks still needed.
```

Reusable review prompt:

```text
Review <base commit>..<head commit> against issue <number>.
Check timer recovery, vault write integrity, sandbox access,
main-thread responsiveness, and compatibility where affected.
Identify actionable defects with a reproduction and file/line.
Check whether test results cover the changed behavior.
Do not change code during the first review pass.
```

For every handoff, include the branch/head commit, problem and expected behavior, files changed, checks with their results, and remaining work. Use synthetic vault examples rather than private notes.

## 4. The daily terminal build, test, and fix loop

### How this project builds with Xcode closed

The repository provides a command-line build route in `scripts/install.sh`. It runs XcodeGen and `xcodebuild`, then copies and launches the result. This explains how an assistant with terminal access on your Mac can build PastelFocus without operating Xcode's editor. The script establishes the available mechanism; it does not establish which commands a previous Claude session actually ran.

| Tool/input | Role in PastelFocus |
| --- | --- |
| `project.yml` | Tracked specification for the macOS app, widget, dependencies, and signing configuration |
| `xcodegen generate` | Generates `PastelFocus.xcodeproj` from the specification |
| `swift test` | Builds and tests `PastelFocusCore`, the library declared in `Package.swift` |
| `xcodebuild` | Builds the macOS app bundle and embedded widget using Xcode's compiler, SDKs, and signing tools |
| `open <path-to-app>` | Launches the built app through macOS |
| App executable + `--render-snapshots` | Uses this project's rendering mode to produce panel/theme PNGs |

`swift build` or `swift test` alone does not package the menu bar app: this package has no app executable target. XcodeGen generates project configuration; `xcodebuild` performs the actual native app build. See [XcodeGen's usage documentation](https://github.com/yonaskolb/XcodeGen#usage) and [Apple's command-line build guide](https://developer.apple.com/library/archive/technotes/tn2339/_index.html).

**The full Xcode installation is still required, even while its window is closed.** The standalone Command Line Tools package does not include `xcodebuild`. Complete initial toolchain setup and select the intended Xcode installation. Signed builds also need the appropriate certificates/private keys, provisioning, registered App Group, and credentials. See [Apple's tool installation guidance](https://developer.apple.com/documentation/xcode/installing-the-command-line-tools/).

Check the environment before assigning build work:

```bash
cd /Users/ammar/Projects/PastelFocus
xcode-select -p
xcodebuild -version
swift --version
xcodegen --version
```

On 7 October 2026, this Mac selected `/Applications/Xcode.app/Contents/Developer` and reported Xcode 27.0, Swift 6.4, and XcodeGen 2.46.0. Keep these checks in the assistant's build report when investigating toolchain differences.

The assistant needs a Mac execution environment for SwiftUI/AppKit/WidgetKit builds. A cloud session that only edits GitHub files should hand its commit to your local Mac or a macOS CI runner for native verification. It should report native builds as unverified until that execution happens.

### Branch, test, and build

Start with a clean working tree. If changes were merged remotely, bring them down with `git pull --ff-only`; if you have local edits, commit or deliberately preserve them first. Pulling is unnecessary just because you pushed changes already present locally.

For a new code task:

```bash
git switch main
git pull --ff-only
git switch -c codex/short-description
swift test
xcodegen generate
xcodebuild -project PastelFocus.xcodeproj \
  -scheme PastelFocus -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build build
```

These are separate commands; continue only when each required step succeeds. The Debug app is produced at `build/Build/Products/Debug/PastelFocus.app`. The signed app build needs your local signing configuration for the App Group. The installer adds `-allowProvisioningUpdates`, which permits Xcode to update provisioning using configured credentials; use that option deliberately when needed.

For a compilation check without signing credentials, add `CODE_SIGNING_ALLOWED=NO` to the build command. Do not use an unsigned build as evidence that App Groups, widgets, notifications, login items, or distribution signing work.

XcodeGen's `project.yml` is the project source of truth; the generated `.xcodeproj` is ignored, so persistent target/capability changes belong in `project.yml` and the tracked source/configuration. Assistants can edit these files directly; they do not need Xcode's project editor.

For a bug, reproduce it first. Add a failing regression test for meaningful timer, persistence, parser, or concurrency behavior, then fix it. For a visual hit-area adjustment, a direct interaction check is usually more useful than a test that repeats the implementation.

Use the checks that fit the change:

| Change | Required evidence before merge |
| --- | --- |
| Core logic, vault writes, timer state | Relevant regression tests plus the complete fast core suite |
| SwiftUI/AppKit or shared rendering | App/widget build plus actual interaction check; core suite if shared logic changed |
| Theme tokens | Palette/contrast tests plus representative light/dark rendering |
| Signing, entitlements, App Groups, login, or notifications | A signed installed build and the relevant permission/lifecycle checks |
| State or schema migration | Old-version fixture upgrade, interrupted/repeated migration, and failure recovery |
| Documentation only | Check links, commands, and consistency |

### Launch and inspect without Xcode

Run the following example from a **separate macOS test account** until development isolation is complete. Put a checkout in that account's `~/Projects/PastelFocus` and run the build steps there first. This example configures a disposable vault before the app initializes. The `ui` suffix matches `PASTELFOCUS_DEV=ui`.

```bash
cd ~/Projects/PastelFocus
mkdir -p /private/tmp/PastelFocus-ui-vault/Daily
defaults write com.ammarghazal.pastelfocus.dev.ui vaultPath -string /private/tmp/PastelFocus-ui-vault
defaults write com.ammarghazal.pastelfocus.dev.ui dailyFolder -string Daily
defaults write com.ammarghazal.pastelfocus.dev.ui logsInVault -bool true
PASTELFOCUS_DEV=ui ./build/Build/Products/Debug/PastelFocus.app/Contents/MacOS/PastelFocus
```

Direct execution passes the environment into this new process and keeps terminal output available. The process continues until you quit the app. This is a native macOS app: look for its menu bar item and desktop panels; `LSUIElement=true` intentionally suppresses a normal Dock icon. No iOS Simulator is involved.

For the next iteration, quit this development copy using its menu, rebuild, and execute the new binary. Keep process control specific to the development copy; do not kill every process named PastelFocus. Avoid `open` for launching a named development environment unless you deliberately pass that environment through macOS's launch mechanism.

After quitting the interactive copy, an assistant can render the project's visual checks from the same test environment:

```bash
PASTELFOCUS_DEV=ui ./build/Build/Products/Debug/PastelFocus.app/Contents/MacOS/PastelFocus \
  --render-snapshots /private/tmp/PastelFocus-ui-snapshots
```

Inspect the generated PNGs; the rendering code can suppress file errors, so an exit code alone is insufficient. This mode needs a logged-in graphical Mac session and initializes the model before rendering. It checks appearance, not mouse hit areas, window focus, notification permissions, or shipping widget behavior. Development mode disables widgets; validate those separately with a signed, production-equivalent build.

The routine manual check takes about 5–10 minutes: menu opens; Settings/Insights appear; panel controls work on their first click; dial drags and keyboard adjustment work; start/pause/resume/stop work; a task edit reaches the fixture vault; external edits reach the app; a theme change updates visible panels; Quit exits cleanly; a relaunch restores expected state.

### Install a passing build for daily use

After merge, install the passing Release build for personal daily use. Once the install script's failure handling is corrected, `./scripts/install.sh` provides the one-command generate → Release build → replace → relaunch route. It installs at `~/Applications/PastelFocus.app`; it is not an App Store upload or release.

For a successfully installed personal copy, `open ~/Applications/PastelFocus.app` launches it. If that copy is already running, `open` can simply activate the existing process, so quit it before expecting a newly built version to run. Keep the last known-good app and a backup of valuable data when testing changes to persistence.

Use Xcode's interface when it helps with previews, graphical debugging, Instruments, or first-time signing setup. Routine edits, tests, builds, and launches can stay terminal-driven.

## 5. Automated checks on GitHub

Add a GitHub Actions workflow for PRs and pushes to `main` using a macOS runner and an explicitly selected Xcode version. Record the runner, Xcode, Swift, and XcodeGen versions; deliberately upgrade the toolchain in its own change.

Required jobs:

1. **Core tests:** `swift test`.
2. **Native build:** generate the project, then compile the app and embedded widget in Debug and Release. An unsigned compilation can use `CODE_SIGNING_ALLOWED=NO`; it proves compilation, not entitlement or distribution correctness.
3. **Configuration checks:** validate plists and version alignment. Add targeted checks for capabilities/manifest resources when those are established.

Use stable check names and run every required check on each PR. Retain logs and useful build/test reports on failure. Formatting/lint checks are useful once configured, but should not create large unrelated rewrites.

Protect `main` against force pushes and require PRs and passing checks. Require another person's approval if you have a collaborator; for a solo project, do not make the process depend on approving your own PR. Use the independent AI review and your recorded acceptance checklist. See [GitHub's branch protection documentation](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches).

Keep signed archives/uploads in a separate, deliberately triggered terminal release workflow; Xcode Organizer is an optional alternative. Routine pushes may run CI; they should not automatically publish an App Store version. Keep certificates, provisioning secrets, and App Store Connect credentials in managed credentials or CI secrets.

## 6. macOS menu bar engineering rules

- **Keep the existing core/UI split.** Put timer rules, Markdown parsing, analytics, and migrations in the core. Keep AppKit panels and system services at the app boundary.
- **Keep UI responsive.** Publish UI state on the main actor; move expensive scans, SQLite work, and report generation off it using a serialized worker or actor. Avoid multiple writers racing over shared state.
- **Treat clocks as data.** Derive elapsed time from a defined clock policy rather than counting timer callbacks. The current engine interrupts running sessions after sleep longer than 120 seconds; retain or deliberately revise that policy and its tests. Cover clock changes, timezone changes, and daylight saving boundaries as well as restart recovery.
- **Minimize idle work.** Stop a one-second ticker when idle; use timer tolerance where appropriate. Debounce file events and avoid writing unchanged output. The current ticker still fires while idle even though its callback returns early. See [Apple's guidance on timer energy use](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html).
- **Measure animation cost.** Core Animation reduces app-side drawing, but WindowServer/GPU work still uses energy. Respect Reduce Motion, pause unnecessary hidden animation, and measure total impact rather than assuming animation is free.
- **Make the app easy to control.** Keep Settings and Quit discoverable, manage window focus deliberately, handle multiple displays and Spaces, and ensure saved frames cannot strand panels offscreen.
- **Use public system APIs and least privilege.** Keep `MenuBarExtra` unless you need behavior it cannot provide; use AppKit for justified panel behavior. Keep `SMAppService` for login management and display its actual status. Handle shortcut collisions and registration failures.
- **Design permissions into the feature.** Ask for notifications at a useful moment, handle refusal, and keep timers usable without alerts. A denied vault permission should offer folder reselection rather than silently showing an empty task list.
- **Protect data and expose failures.** Preserve unknown Markdown, surface failed saves, and keep logs recoverable. Atomic replacement and a pre-write signature check do not by themselves prove cross-process lost-update protection; stress-test concurrent Obsidian/Hermes/app writes and use coordination or conflict preservation where needed.
- **Make widgets eventually consistent.** Keep atomic snapshots in the entitled App Group. Deduplicate commands, handle the app being closed, and accept that WidgetKit schedules refreshes; do not promise real-time widget updates.
- **Support accessibility.** Give controls labels, keyboard access, visible focus, and usable click targets. Check VoiceOver, Increase Contrast, Reduce Transparency, and Reduce Motion.
- **Log useful diagnostics.** Use structured unified logging for permission, file, timer, and migration failures without exposing task text or private paths. Include app version/build in an About or diagnostics view.

See [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra) and [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice).

## 7. The checks before a release candidate

Use a **Release build installed normally**, with production-equivalent sandboxing, signing, App Groups, and permissions. A development build with widgets disabled cannot validate shipping widget behavior.

| Area | Check |
| --- | --- |
| First launch | Fresh macOS account, no existing preferences, no Hermes/Obsidian, folder selection/cancel, usable empty state |
| Permissions | Notifications allowed/denied; folder grant, relaunch, moved folder, stale bookmark, missing volume, access failure |
| Lifecycle | Quit/relaunch during running and paused sessions; completion while hidden; short/long sleep; login/logout and restart |
| Time | Midnight, month rollover, DST in a test timezone, timezone/clock changes, stale restored sessions |
| Vault integrity | Simultaneous external edits, duplicate IDs, malformed/truncated records, read-only files, save errors, large fixture vault |
| UI | First click, dial hit area, keyboard navigation, dragging, multiple monitors, display disconnect, Spaces/fullscreen |
| Appearance | Representative palettes for every theme, light/dark matching, accessibility settings, hidden-panel motion |
| Widgets | Add/remove each widget, commands with app open/closed, snapshot recovery, stale state, correct App Group access |
| Login and shortcuts | Explicit opt-in/out, system-disabled login service, error state, shortcut collision |
| Upgrade | Previous released data/preferences/state into candidate; sandbox-container migration; failed and repeated migrations |
| Performance | Idle, active timer, animated themes, hidden panels, file-change burst, and a long-running session |

Test on the current shipping macOS and the oldest version you advertise. The current deployment target is macOS 14; support needs evidence on macOS 14, not just successful compilation on the developer machine. Test Intel hardware if you ship an Intel slice, and verify archive architectures instead of assuming a build on Apple silicon is universal.

Use deterministic fixtures and the injected clock for unit tests. Test OS lifecycle and permission behavior on an actual Mac. Screenshots help assess layout; they do not verify hit areas or focus. Add a few XCTest UI flows for critical controls rather than attempting to automate every OS permission dialog.

Profile Release with Activity Monitor and appropriate Instruments for CPU, memory, hangs, file activity, and energy. Track a baseline for idle and active use. Investigate sustained idle CPU, frequent wakeups, growing memory, visible input delays, and repeated unchanged writes. README performance estimates are targets to measure, not guarantees.

## 8. When to release

Release because there is a useful, validated change, not because a commit was pushed.

| Situation | Decision |
| --- | --- |
| Internal cleanup with no user benefit | Merge after checks; include in a later release |
| Small ordinary fixes or improvements | Batch a coherent update; weekly or fortnightly is a reasonable starting cadence |
| Meaningful new feature | Beta test, meet acceptance criteria, then release when ready |
| Data loss, security defect, launch failure, or broken core timer | Prioritize a focused fix; shorten beta time while retaining relevant regression, recovery, and archive checks |
| macOS compatibility problem | Fix and test on the affected OS before releasing the update |

For the first public version, first make onboarding and sandboxed storage reliable, then give **3–5 testers roughly a week** of normal use. This is a suggested starting point, not an Apple requirement. Extend testing if issues appear; days elapsed alone are not a release gate.

A candidate is ready when:

- Its exact commit passes CI, independent review, and acceptance checks.
- No known data-loss, security, launch, or core-workflow blocker remains.
- Clean installation and upgrade preserve data and settings.
- The signed beta works with real permissions, login behavior, and widgets.
- Performance is acceptable against the recorded baseline.
- Store metadata, privacy/support links, review notes, and release notes match the build.

Do not wait for every feature on the roadmap. Choose a small public promise and make that dependable. Cosmetic issues can be deferred if they do not impair use.

## 9. Versioning, TestFlight, and App Store submission

Use a simple version policy: `1.0.1` for fixes, `1.1.0` for compatible features, and `2.0.0` for a deliberately substantial or incompatible change. A major version number does not replace a data migration.

Use an increasing integer build number for each upload. One public version may have several beta builds. Drive `CFBundleShortVersionString` and `CFBundleVersion` from `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the generated configuration; verify that both app and widget resolve to the intended values.

Before the first store beta:

1. Configure the Apple Developer account, bundle identifiers, App Group, signing, and App Store Connect app record.
2. Enable the main app sandbox. Replace a typed vault path as the authorization mechanism with a system folder picker, read/write user-selected access, and persistent security-scoped bookmarks. Resolve/refresh stale bookmarks and balance access calls. Plan migration of existing private support data into sandbox-managed storage. See [Apple's sandbox file-access guidance](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox).
3. Prepare the app icon, screenshots, description, support contact, privacy policy, age rating, and applicable export-compliance answers. Link the privacy policy in App Store Connect and inside the app, as required by [App Review Guidelines, section 5.1.1](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage).
4. Audit actual data handling, including dependencies and optional external-agent integration. On-device processing alone is not considered collection for the privacy label; sending data elsewhere can change the answers. See [App privacy details](https://developer.apple.com/app-store/app-privacy-details/).
5. Audit privacy-manifest rules for the final macOS target. No manifest is tracked today. Do not assume an iOS required-reason API rule automatically applies to macOS or copy approved reason codes without checking applicability. If included, a valid macOS privacy manifest belongs in the app's resources; see [Apple's manifest documentation](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk).
6. Check the current accepted toolchain and upload requirements at release time. Record the chosen production Xcode version. The latest SDK used to build and the minimum OS customers can run are separate settings. See [Xcode requirements](https://developer.apple.com/xcode/system-requirements) and [upcoming submission requirements](https://developer.apple.com/news/upcoming-requirements/).

For each candidate:

1. Freeze a tested commit and set version/build values. Avoid merging new features into that candidate.
2. Create a Release archive using `xcodebuild archive` or Xcode Organizer, then export/validate it with the appropriate production distribution configuration. Check the resolved entitlements, embedded widget, versions, architectures, resources, and absence of development overrides.
3. Upload to App Store Connect and test that processed build through TestFlight. External testing can require beta review; builds expire after 90 days. See [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/).
4. If fixes are needed, create a new build number and repeat the affected checks. Select the same tested App Store Connect build for submission.
5. Provide review notes explaining that the app lives in the menu bar, how to open Settings, how to choose/create a sample vault, and how to use the timer/widgets. Make the core feature testable without private notes or Hermes access.
6. Submit for review with manual release control. After approval, release when you can monitor feedback and address problems.
7. Tag the released source commit, for example `v1.0.0`, and record its build number, commit, toolchain, and release notes. Preserve the signed archive and dSYMs outside Git.

A terminal archive command, after generating the project and configuring the candidate's signing, is:

```bash
xcodebuild -project PastelFocus.xcodeproj \
  -scheme PastelFocus -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build \
  -archivePath build/archives/PastelFocus.xcarchive archive
```

Choose a distinct archive path for each candidate you intend to retain. Archiving is not the same as uploading or releasing. Configure and review a distribution export-options plist, then use `xcodebuild -exportArchive` and a supported authenticated upload route. Apple's tools can upload without Xcode's editor; see [uploading builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/). Store metadata, beta distribution, submission, and release decisions remain explicit stages. The repository does not yet contain a configured store export/upload script.

Use the Mac App Store for updates to the store-distributed app; its own downloader or GitHub push is not a store update mechanism. This is required by [App Review Guidelines, section 2.4.5(vii)](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility).

For subsequent versions, consider Apple's seven-day phased rollout for automatic updates. It can be paused if trouble appears, but users can still manually download the update. It does not provide a downgrade of already-updated installations. See [phased releases](https://developer.apple.com/help/app-store-connect/update-your-app/release-a-version-update-in-phases/).

## 10. After release and when something goes wrong

Review crash reports, tester/support feedback, and new regressions during the first few days of a release. Record the version/build, macOS version, reproduction, and sanitized diagnostics with each issue. Use the workflow to turn each report into a focused fix.

For a serious regression, pause a phased rollout if active, preserve user data, reproduce against the released build, and prepare a compatible patch from the release commit. Merge the fix back into `main` if main has moved on. Retest the failing path, data recovery, and upgrade, then upload a higher build/version and request expedited review when justified.

Do not treat reverting Git or removing a store listing as a rollback of installed apps. Recovery for store users normally means shipping a corrected update; prevent irreversible data changes through migration design and backups.

Recommended next work, in order: reliable install script and complete dev isolation; PR CI; sandboxed folder access and storage migration; first-run/permission behavior and version configuration; then a small TestFlight beta and the first public release.
