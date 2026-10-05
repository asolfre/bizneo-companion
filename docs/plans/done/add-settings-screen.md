# Plan: Native Settings Screen for Bizneo Companion

Goal: replace the current "Edit configuration…" action (which opens the raw
`config.json`) with a native **Settings…** window that edits every option through
proper controls, saves to the same `config.json`, and applies immediately — no
restart, no manual JSON editing.

## Decisions (confirmed)

- **Field scope:** full grouped settings (Account / Display / Clock / Time off /
  General / Advanced).
- **Open at login:** yes — via `ServiceManagement` `SMAppService.mainApp`.
- **Test connection:** ~~yes~~ **deferred** — see *Deferred scope* below.
- **Auto-detect dropdowns:** Chrome profiles ~~yes~~ **deferred**; the default-project
  dropdown shipped, since the project list is already in the snapshot.

## Context (current code)

- `Config` already round-trips to JSON via `Config.load()` / `save()` and has a
  tolerant decoder (old config files keep working).
- `StatusItemController` holds a mutable `config`, a rebuildable `client`
  (`BizneoClient(config:)`), and `scheduleTimer()`.
- The latest snapshot exposes `chrono.projects` (id → name) for the project dropdown.
- App runs as a `.accessory` menu-bar agent (no Dock icon); showing a window needs
  `NSApp.activate(ignoringOtherApps:)` + `makeKeyAndOrderFront`.
- Toolchain is Command Line Tools + SwiftPM (no xib/storyboard) → build the window
  in code.

## UI framework: SwiftUI, not hand-built AppKit

Earlier drafts specified `NSGridView` / `NSStackView`, reasoning from "Command Line
Tools, no Xcode". That constraint rules out **xibs and storyboards**, not SwiftUI —
and the two were conflated. `SwiftUI.framework` ships in the CLT SDK
(`/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`) and `Package.swift` already
declares `.macOS(.v13)`, so a `Form` builds fine here; it was confirmed with a
`swiftc -typecheck` spike before any of this was written, along with
`NSHostingController` and `SMAppService`.

A `Form` is roughly a third of the code of seventeen hand-built grid rows, so that's
what shipped. One hard constraint: **plain `@State` / `@Binding` only, never
`@Observable`** — that macro needs swift-syntax, which a CLT-only toolchain can't
build.

## Deferred scope

Two items from the original design were cut. They were about 60% of the projected
code for the least of the window's value, and neither is a regression: both fields
are still editable, just as plain text, exactly as they were when the only editor was
the JSON file. They're carried forward in
[`pending/settings-connection-helpers.md`](../pending/settings-connection-helpers.md)
rather than dropped.

- **Chrome profile auto-detect** — directory enumeration, `Preferences` JSON parsing
  for friendly names, Bizneo-cookie flagging. Shipped as a `TextField`.
- **Test connection** — a temporary `BizneoClient` built from the unsaved form
  values, one `refresh()`, inline result, in-flight disabling, Keychain-prompt
  handling.

## New file: `Sources/BizneoCompanion/SettingsWindowController.swift`

SwiftUI `Form` in an `NSWindow` via `NSHostingController`. Holds a working copy of
`Config` and an `onSave: (Config) -> Void` callback. A strong reference to the window
is kept (`isReleasedWhenClosed = false`).

The hosting controller is **rebuilt on each `show()` unless the window is already on
screen**. Reusing it would preserve SwiftUI's `@State`, so edits abandoned with Cancel
would reappear the next time the window opened; but rebuilding it while the window is
visible would throw away half-typed edits when Settings is clicked a second time, so a
visible window is just brought forward.

**Main menu.** The app is `.accessory` and never set `NSApp.mainMenu`. AppKit routes
⌘X/C/V/A/Z through the main menu's key equivalents, so without one, paste does nothing
in the Settings fields, and the cookie field is the one you have to paste into.
`main.swift` installs a hidden Edit menu (plus ⌘W). It is never displayed: accessory
apps don't own the menu bar. The `⌘,` on the Settings item is the same kind of shortcut
as the existing ⌘R/⌘Q. It works while the status menu is open, not globally.

### Sections & controls

The authoritative field list is `Config`'s custom `init(from:)`
(`Sources/BizneoCore/Config.swift:102-118`) — every key decoded there needs a control
here. Re-check it before touching the form; fields added by plans that ship in the
meantime will not be listed below.

`BarMetric`, `DropdownSecondsScope` and `LeaveByScope` gained `CaseIterable` so the
pickers can enumerate them. The human-readable labels stay in the view: they're UI
copy, and `BizneoCore` has no business holding them.

- **Account**
  - `tenant` — `TextField`, trimmed on save
  - `userId` — `TextField`, trimmed on save
  - `chromeProfile` — `TextField` (see *Deferred scope*)

- **Display**
  - `barMetric` — `Picker` (Today / This week / This month / This year)
  - `refreshSeconds` — `Picker` of presets (1 / 5 / 10 / 15 / 30 / 60 min). A preset
    picker rather than a number field means there's no invalid state to validate and
    no clamp to write; `scheduleTimer()` already floors the interval at 60s
    (`StatusItemController.swift:39`). The current value is unioned into the options
    so a hand-edited interval still has a matching row instead of rendering blank, and
    an interval that isn't a whole number of minutes is labelled in seconds.
  - `weekStartsMonday`, `includePending`, `enableYearTotal`, `liveTick` — `Toggle`
  - `barShowSecondsWhileWorking` — `Toggle`, disabled unless `liveTick`
  - `dropdownSecondsScope` — `Picker` (Never / Today only / Every row), disabled
    unless `liveTick`

- **Clock**
  - `enableClockActions` — `Toggle`
  - `defaultTelework` — segmented `Picker` (Office / Telework)
  - `defaultProjectId` — `Picker` over the snapshot's projects, with a raw-id
    `TextField` fallback when that list is empty (first run, any failed refresh), and
    an extra row when the configured id isn't in the list (an archived project, or an
    id edited by hand). A picker whose selection matches no tag renders blank, which
    SwiftUI warns gives "undefined results". Whether it would also write the value back
    on save was **not observed**. These guards make sure that never needs finding out.
    - **Shadowed by the last-used project.** The quick "Check in" item uses
      `lastProjectId ?? defaultProjectId` (`StatusItemController.swift:425`, `:499`),
      and every pick from the "Check in ▸" submenu sets `lastProjectId`, even
      "No project". On its own, a default edited in Settings would have no effect
      for anyone who had used the submenu. `applyConfig` clears `lastProjectId` when
      the default changes, and the form says so under the picker.
  - `leaveByScope` — `Picker` (Today only / week / month / year), labelled for what it
    does: which backlog the "Leave by" line clears. Shipped in
    [`leave-by-scope.md`](leave-by-scope.md).
    (This was `carryoverScope` in earlier drafts of this plan and sat under
    *Display*, because it was meant to change the menu-bar number; that design was
    dropped as a no-op. It belongs with the clock now.)

- **Time off**
  - `dayOffScheduleNames` — comma-separated `TextField`; split, trimmed, empties
    dropped on save

- **General**
  - **Open at login**: a `Toggle` backed by `SMAppService.mainApp`. This is
    system login-item state, NOT a `config.json` field. `SMAppService.Status` has four
    cases. `.requiresApproval` means the app *is* registered but the user has blocked
    it in System Settings → Login Items, so it counts as "on" and the form shows an
    **Approve in System Settings…** button
    (`SMAppService.openSystemSettingsLoginItems()`).
    - *Corrected after review.* The first version counted only `.enabled` as on and
      drove the toggle through `.onChange`. In the blocked case `register()` throws
      `kSMErrorLaunchDeniedByUser` (`SMAppService.h`), the status reads
      `.requiresApproval`, and the state was set to `false`. `.onChange` then fired
      again and called `unregister()`, which undid the registration the user had just
      asked for, so the toggle could never be turned on. The toggle now writes through
      a `Binding` setter, so writing back the real status can't trigger it again. Other
      errors are shown inline rather than beeped.
    - Apple's header requires the app to be code signed. `build_app.sh` only ad-hoc
      signs, so whether this works on a local build has to be tested at runtime, from
      `/Applications`, across a real logout and login.

- **Advanced**
  - `manualCookie` — `SecureField`
  - **Open config file…** button — one line, `NSWorkspace.shared.open(Config.fileURL)`.
    The file always exists by then: `Config.load()` creates it at launch
    (`Config.swift:130-139`).

- **Footer:** Save / Cancel + `AppInfo.version` label (from [`versioning.md`](versioning.md)).

### Validation

- `tenant` and `userId` required — Save disabled while either is blank.
- `refreshSeconds` — no validation needed, see the preset picker above.
- `dayOffScheduleNames` trimmed, split on commas, empties dropped.

## Wiring in `StatusItemController`

- Menu: **"Edit configuration…" → "Settings…"** (`⌘,`). Raw-file access moves into
  the Settings window's Advanced section, so `openConfig()` is **deleted** — the
  wiring is a net deletion in this file.
- `private var settingsWC: SettingsWindowController?`
- `@objc func openSettings()`: lazily create/reuse the controller, then
  `show(config:projects:)` with the current `config` and
  `latest?.chrono?.projects ?? []`.
- `func applyConfig(_ new: Config)`:
  1. clear `lastProjectId` if `defaultProjectId` changed (see the Clock section)
  2. `try? new.save()`
  3. `self.config = new`
  4. `self.client = BizneoClient(config: new)` (drops cached cookie + year totals)
  5. `scheduleTimer()` (the interval may have changed)
  6. `rebuildMenu(snapshot: latest)`, immediately rather than on the next successful
     fetch: `enableClockActions` and `includePending` change the menu's *structure*,
     and the fetch may fail
  7. `refresh()`

  Earlier drafts had a separate "re-apply the title" step. It's redundant: `refresh()`
  repaints the bar from `barContent()` *before* it awaits
  (`StatusItemController.swift:47-54`), so a new `barMetric` shows instantly.

## Tests / build

- No `BizneoCore` logic changes → existing `--selftest` numbers stay green.
- The existing `Config` round-trip check covered 2 of 17 fields. It was generalised
  to set **every** field to a non-default value, re-encode after the round-trip, and
  report any line that went missing. This is the only automated guard for the
  `AGENTS.md` gotcha where a forgotten `decodeIfPresent` line silently drops a field —
  which now matters more, because Settings writes the whole struct back to disk, so a
  dropped field means the window overwrites a real value with a default.
  Verified by sabotage: deleting the `chromeProfile` decode line makes the check fail
  and name that exact field.
- Rebuild `BizneoCompanion.app`.

## Notes / risks

- **AppKit window from an agent app:** handled via `NSApp.activate` +
  `makeKeyAndOrderFront`; strong reference retained.
- **Launch-at-login reliability:** `SMAppService` registers the app at its current
  path. If the build lives in a cloud-synced folder, login items from such a path
  (spaces, sync delays) can be flaky. For dependable auto-start, move
  `BizneoCompanion.app` to `/Applications`. Noted in both the UI and the README.
- All fields already exist in `Config` with a tolerant decoder, so older
  `config.json` files keep working.
