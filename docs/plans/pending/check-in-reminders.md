# Plan: Check-in reminders

Issue: [#16](https://github.com/asolfre/bizneo-companion/issues/16). *If it's a workday,
you're not on vacation or similar, the screen is on and you're checked out, send
reminders inside defined time ranges (e.g. 08:00-10:00; 14:00-15:30).*

The menu bar already turns orange when you forget to check in. That only works if
you look at it. This adds a nudge you can't miss, with a button that fixes the
problem in one click.

## Decisions

Taken in an interview, then amended after an adversarial review (R1–R7 below).

| Topic | Decision |
|---|---|
| What reminds | `notCheckedIn` (morning), `checkedOutEarly` (forgot to come back after lunch), `onBreak` (forgot to resume) |
| Breaks | **No minimum length.** A coffee break can get a reminder if the interval falls inside it. Chosen deliberately; a grace field can come later if it annoys. |
| "Screen on" | Display awake **and** session unlocked, and this user is the one at the console |
| Delivery | macOS notification with **Check in** (or **Resume** when on a break) and **Not today** |
| Interval | Setting, 5 / 10 / **15** / 30 / 60 minutes |
| Windows | Setting, one text field: `08:00-10:00, 14:00-15:30`. **On by default.** |
| On/off | A switch in Settings, separate from the windows, so turning reminders off doesn't lose them |
| Vacation | **Unknown** whether Bizneo zeroes expected hours on vacation days. Covered by the locked-screen rule plus **Not today**. Check what the menu bar shows on the next absence day; parse absences only if it shows orange. |

Already settled by existing code: no expected hours today (weekend, holiday,
company day off) is `BarState.offDuty` (`BarState.swift:46`) and never reminds.
`.unknown` never reminds either.

## Design

### `BizneoCore`

- **`Config`**: three fields, each with its `decodeIfPresent` line (the AGENTS.md
  gotcha): `remindersEnabled` (`true`), `reminderWindows`
  (`["08:00-10:00", "14:00-15:30"]`), `reminderIntervalMinutes` (`15`).
- **`Reminders.swift`**: pure functions, all covered by `--selftest`:
  - `parseWindow("08:00-10:00")` → `480..<600`. Reuses `TimeFmt.parseHM` for each end;
    rejects signs, times outside 00:00–23:59, and windows that cross midnight or are
    empty. An invalid entry is **ignored** at runtime (`config.json` can be hand-edited)
    and **blocks Save** in Settings.
  - `next(context, justRefreshed:)` → `idle` / `refresh` / `remind` / `failureNotice` /
    `wait`. Takes the time and the calendar as inputs, so the self-test controls them.
- **`ChronoAction.isAllowed(from:)`** + a guard in `BizneoClient.performChrono` (R1).

### App

- A **60-second timer** in `.common` run-loop mode, so it keeps going while the status
  menu or an alert is open (R7). Each tick asks `Reminders.next`, and on `refresh`
  awaits a refresh and asks again with `justRefreshed: true`.
- **Screen state** is read at each tick, no observers: `CGDisplayIsAsleep` on the main
  display, `kCGSessionOnConsoleKey` (documented) for fast user switching, and the
  undocumented `CGSSessionScreenIsLocked`. A **missing lock key counts as unlocked**
  (R4), so the feature falls back to "display awake" rather than going silent.
- **Notifications** (`ReminderNotifier.swift`): `UNUserNotificationCenter`, only when
  running from an app bundle (it crashes under `swift run` / `--selftest`).
  - Two button sets: *Check in · Not today* and *Resume · Not today*. With clock
    actions disabled in Settings, only *Not today*.
  - One fixed identifier, so a new reminder replaces the last instead of stacking.
  - `willPresent` returns a banner, otherwise macOS hides it while Settings is open (R7).
  - Permission is requested **at launch or when reminders are switched on**, never at
    the moment a reminder is due (R7).
- **Buttons** reuse the menu's paths: quick check-in (`lastProjectId ?? defaultProjectId`)
  and resume. **Not today** stores the Madrid date in `UserDefaults`.

## Review findings folded in

| ID | Finding | Resolution |
|---|---|---|
| R1 | `performChrono` fetched fresh state but posted regardless of it (`BizneoClient.swift:244`). A reminder pressed after checking in on the phone would send a second "start". What Bizneo does with that is unknown, and must not be tested on a real timesheet. | **Every** clock action, menu included, is refused when the fetched state doesn't allow it. Delivered reminders are cleared whenever a reminder stops being due (`idle`), not only on "working". No reminders while a clock action is in flight. |
| R2 | "If the refresh fails, don't remind" made the feature silent on its most likely failure day: an expired session. | Inside a window, one **"Can't check your Bizneo status"** notice per window, with **Open Bizneo**, after the app's own retry also fails. **Not today** silences it too. |
| R3 | A failed clock action's `NSAlert.runModal()` from an inactive menu-bar app could open behind other windows, pausing the refresh timer, while you believed you were checked in. | `doClock` activates the app before the alert. Fixes the menu path too. |
| R4 | The lock flag is undocumented (`CGSession.h` lists five keys, not that one). | Missing key → unlocked. Log the session dictionary during manual testing. |
| R5 | State changes were only noticed on the scheduled refresh, up to `refreshSeconds` (as much as 60 min). | Inside a window, refresh whenever the last success is older than the reminder interval. |
| R6 | No calendar was named. Bizneo's "today" is Europe/Madrid (`Calculator.swift:6-9`). | Windows and **Not today** use `Calculator.madridCalendar`. |
| R7 | Banners hidden while the app is frontmost; first reminder spent on the permission prompt; default-mode timer paused by menus and alerts. | `willPresent`, permission at launch/enable, `.common` timer. |

## Tests

- `--selftest`: window parsing (valid, invalid, signs, out of range, midnight-crossing,
  empty), every branch of `next` (state × window edges × interval × Not today × screen
  × stale data × failure noticed or not), `ChronoAction.isAllowed`, and the all-fields
  `Config` round-trip with the three new fields. One deliberately broken rule must make
  it fail.
- Manual (only on a real Mac session):
  - permission prompt appears at launch
  - notifications work on an ad-hoc-signed build
  - **Check in** / **Resume** from a reminder work
  - **Not today** silences reminders for the day
  - a locked screen stays silent
  - a junk `manualCookie` produces one failure notice per window, and a clock action
    with it shows its error alert in front
  - the session dictionary, logged once locked and once unlocked

## Out of scope

Forgot-to-check-out reminders and per-weekday windows. Neither is in the issue, and
gating on the logged-vs-target state already does what per-weekday windows would.
A one-click on/off item in the menu-bar dropdown was offered and declined: the Settings
switch plus **Not today** cover it.
