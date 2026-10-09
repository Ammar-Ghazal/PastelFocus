# PastelFocus task format

**Format version 2** (2026-10). Shared by PastelFocus and every agent working with the vault (Hermes, Codex, Claude Code). It describes how tasks, schedules, tags and task metadata are written, so both sides write the same lines and neither has to rewrite the other's output.

The parser is the reference: [`TaskLineParser.swift`](../Sources/PastelFocusCore/Model/TaskLineParser.swift), [`TaskTime.swift`](../Sources/PastelFocusCore/Model/TaskTime.swift) and [`Recurrence.swift`](../Sources/PastelFocusCore/Model/Recurrence.swift), with examples in the tests. If this page and the parser disagree, the parser wins; please report it.

Version 1 used `[est:: N]` and `[sessions:: N]`. The app still reads them and rewrites them as `[spent:: …]` (see [Migration](#migration-from-version-1)).

## Where tasks live

| File | What it holds | Who writes it |
| --- | --- | --- |
| `<daily folder>/YYYY-MM-DD.md` | That day's task lines (under `## Today's task list`) | The app; you by hand; agents **only through the Inbox** |
| `PastelFocus/Backlog.md` | Tasks not tied to a day yet, or planned for a later day | Same as above |
| `PastelFocus/Inbox.md` | Commands for the app, one per line | Agents and you append; the app ticks each with its result |
| `PastelFocus/Now.md`, `Insights.md`, `Stats/`, `Logs/`, `Garden/`, `Problems.md` | App output | The app only |

The daily folder is set in Settings (currently `LLM Wiki/Career/Daily Plans`). The app scans **every checkbox line** in every immediate `.md` file of that folder, plus `Backlog.md`. Never put example, draft or report checkboxes in those files. Reports, proposals and plans belong elsewhere (for Career, `Reports/`).

## A task line

```text
- [ ] 07:00 - 07:45 Job pipeline — scan and triage 25 leads #career [spent:: 25m] [progress:: 40] ⏫ 🔁 every weekday ➕ 2026-10-08 ⏳ 2026-10-09 📅 2026-10-10 🆔 zzwi
    - notes are indented plain bullets under the line
```

Parts, in the order the app writes them:

| Part | Meaning | Written by |
| --- | --- | --- |
| `- [ ]` | Status: `[ ]` to do, `[/]` in progress, `[x]` done, `[-]` cancelled | anyone (agents via Inbox) |
| `07:00` or `07:00 - 07:45` | Time of day it's planned for, 24-hour; a range also gives its length. Must come first. `–` and `to` are read too. | anyone |
| `Title — detail` | The text. ` — ` (spaced em dash) splits title from detail. Keep it on one line. | anyone |
| `#tag` | Tags. The **first** one (skipping `#later`) is the category and decides the garden plant. Reuse tags from `PastelFocus/Tags.md`. `#later` defers a task. | anyone |
| `[spent:: 1h 25m]` | Focus time logged on the task, from the sessions log. | **app only** |
| `[progress:: 40]` | How much of the whole task is done, 0–100, reported after a session. 100 completes the task. | app; agents via `progress` |
| `[duration:: 45m]` | Planned length when there's no start time. With a start time, use a range instead. | anyone |
| `🔺` `⏫` `🔼` `🔽` | Priority: urgent, high, medium, low. No emoji means none. (`⏬` is read as low.) | anyone |
| `🔁 every …` | Repeat rule, see below | anyone |
| `➕ YYYY-MM-DD` | Created | app |
| `🛫 YYYY-MM-DD` | Starts: the first day work can begin | anyone |
| `⏳ YYYY-MM-DD` | Scheduled: the day it's planned for. Without one, a task in a daily note is planned for that note's day; a Backlog task without one is unscheduled. | anyone |
| `📅 YYYY-MM-DD` | Due | anyone |
| `✅ YYYY-MM-DD` | Completed | app |
| `🆔 abcd` | ID, unique across the vault. The app adds one to any line without it. | **app only** |

Durations (`spent`, `duration`) are written as `25m`, `2h` or `1h 25m`. `85m`, `1h25m`, `45 min` and bare minutes are read too.

### Repeat rules (`🔁`)

The words of the Obsidian Tasks plugin, of which the app understands:

| Rule | Lands on |
| --- | --- |
| `every day`, `every 3 days` | every N days |
| `every week`, `every 2 weeks` (also `biweekly`, `every other week`) | the same weekday every N weeks |
| `every week on Monday, Thursday`, `every 2 weeks on Friday`, `every Tuesday and Friday` | those weekdays, every N weeks |
| `every weekday` | Monday–Friday |
| `every weekend` | Saturday and Sunday |
| `every month`, `every 2 months` | the same day of the month |
| any of the above + ` when done` | counted from the day it's done, not the day it was planned |

A repeating task is **one line**: its current occurrence, with `⏳` on the day it's for. The app never lists a routine's future days. Don't write a copy for each day. A rule the app can't read is kept as text, and the task still counts as repeating.

## Changing tasks: the Inbox

Agents change existing tasks only through `PastelFocus/Inbox.md`. Append one unchecked line per command and never edit or reorder older lines. Add ` — reason: …` to explain.

```text
- [ ] create 07:00 - 07:45 Job pipeline #career ⏫ 🔁 every weekday ⏳ 2026-10-09 — reason: agreed routine
- [ ] reschedule 🆔 zzwi ⏳ 2026-10-10
- [ ] priority 🆔 zzwi urgent|high|medium|low|none
- [ ] progress 🆔 zzwi 60
- [ ] complete 🆔 zzwi · reopen 🆔 zzwi · cancel 🆔 zzwi · later 🆔 zzwi
- [ ] suggest-focus 🆔 zzwi 40m · start-focus 🆔 zzwi 25m · link-session s1a2b3c4 🆔 zzwi
```

- **`create`** takes a task line without the checkbox and without `🆔`, `[spent::]` or `✅`; the app adds those. It puts the task in today's note when it's scheduled for today or has no date, and in `Backlog.md` otherwise.
- **Results:** the app ticks each command with `→ created 🆔 …`, `→ applied HH:MM by …` or `→ error: …`. An unticked command is still queued, for example because the app isn't running. Never resend it as a new command.
- **Removed:** `estimate` (version 1) is no longer accepted.

## Rules for writers

1. **One line per task.** To move a task to another day, `reschedule` it rather than copying it.
2. **Don't touch app fields.** `🆔`, `[spent::]`, `✅`, `➕` and the generated sections of daily notes (`## Focus log`, `## PastelFocus summary`) belong to the app.
3. **Preserve unknown text.** The app rewrites only the line it changes and keeps unknown text on it. Agents must leave other lines alone.
4. **ISO dates and 24-hour times.** Never relative words ("tomorrow") in fields.

## Migration from version 1

- **Old fields:** `[est:: N]` is dropped. `[sessions:: N]` becomes `[spent:: …]`, using the time in the sessions log, or N × 25 min when the log has nothing for the task.
- **When:** the app does this on its next refresh and first copies each file it changes to `~/Library/Application Support/PastelFocus/Backups/`.
- **Create commands:** an `[est:: N]` in a create command is ignored.
