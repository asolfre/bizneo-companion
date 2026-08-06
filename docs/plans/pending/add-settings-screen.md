# Plan: Native Settings Screen for Bizneo Companion

Goal: replace the current "Edit configuration…" action (which opens the raw
`config.json`) with a native **Settings…** window that edits every option through
proper controls, saves to the same `config.json`, and applies immediately — no
restart, no manual JSON editing.

## Decisions (confirmed)

- **Field scope:** full grouped settings (Account / Display / Clock / Time off /
  General / Advanced).
- **Open at login:** yes — via `ServiceManagement` `SMAppService.mainApp`.
- **Test connection:** yes — validate account settings before saving.
- **Auto-detect dropdowns:** yes — Chrome profiles and default project as dropdowns
  with editable/custom fallback.

## Context (current code)

- `Config` already round-trips to JSON via `Config.load()` / `save()` and has a
  tolerant decoder (old config files keep working).
- `StatusItemController` holds a mutable `config`, a rebuildable `client`
  (`BizneoClient(config:)`), and `scheduleTimer()`.
- The latest snapshot exposes `chrono.projects` (id → name) for the project dropdown.
- App runs as a `.accessory` menu-bar agent (no Dock icon); showing a window needs
  `NSApp.activate(ignoringOtherApps:)` + `makeKeyAndOrderFront`.
- Toolchain is Command Line Tools + SwiftPM (no xib/storyboard) → build the window
  programmatically.

## New file: `Sources/BizneoCompanion/SettingsWindowController.swift`

Programmatic AppKit window (`NSGridView` / `NSStackView`). Holds a working copy of
`Config` and an `onSave: (Config) -> Void` callback. Keeps a strong reference so it
isn't deallocated; reused on reopen.

### Sections & controls

- **Account**
  - `tenant` — `NSTextField`
  - `userId` — `NSTextField`
  - `chromeProfile` — `NSPopUpButton` auto-detected from
    `~/Library/Application Support/Google/Chrome/*/` dirs that contain a `Cookies`
    file; friendly names from each profile's `Preferences` JSON (`profile.name`);
    profiles with a `*.bizneohr.com` cookie flagged; editable/custom fallback.
  - **Test connection** button — builds a temporary `BizneoClient` from the *current
    form values*, runs one `refresh()`, shows inline result
    ("✓ Connected · working since 09:48" or the exact error). Disabled while running.
    May trigger the one-time Keychain prompt.

- **Display**
  - `barMetric` — `NSPopUpButton` (Today / This week / This month / This year)
  - `refreshSeconds` — `NSPopUpButton` presets (1 / 5 / 10 / 15 / 30 / 60 min)
  - `weekStartsMonday` — checkbox
  - `includePending` — checkbox
  - `enableYearTotal` — checkbox

- **Clock**
  - `enableClockActions` — checkbox
  - `defaultTelework` — segmented (Office / Telework)
  - `defaultProjectId` — `NSPopUpButton` ("None" + projects from latest snapshot) +
    "Custom ID…" fallback

- **Time off**
  - `dayOffScheduleNames` — token field or comma-separated text

- **General**
  - **Open at login** — checkbox backed by `SMAppService.mainApp`
    (read `.status`, toggle `register()` / `unregister()`). System login-item state,
    NOT a `config.json` field.

- **Advanced** (disclosure, collapsed)
  - `manualCookie` — `NSSecureTextField`
  - **Open config file…** button (reveals the raw JSON for power users)

- **Footer:** Save / Cancel + app version label.

### Validation

- `tenant` and `userId` required (Save disabled if empty).
- `refreshSeconds` clamped to ≥ 60.
- `dayOffScheduleNames` trimmed, split on commas, empties dropped.

## Wiring in `StatusItemController`

- Menu: change **"Edit configuration…" → "Settings…"** (`⌘,`). Raw-file access moves
  into the Settings window's Advanced area.
- `private var settingsWC: SettingsWindowController?`
- `@objc func openSettings()`: lazily create/reuse the window with the current
  `config` and `latest?.chrono?.projects ?? []`; `NSApp.activate(ignoringOtherApps: true)`
  + bring window to front.
- `func applyConfig(_ new: Config)`:
  1. `try? new.save()`
  2. `self.config = new`
  3. recreate `self.client = BizneoClient(config: new)` (resets cookie/year caches)
  4. `scheduleTimer()` (interval may have changed)
  5. re-apply title from `latest` (so `barMetric` changes show instantly)
  6. `refresh()`

## Helpers

- Chrome profile enumeration + friendly names + Bizneo-cookie flag.
- Default-project list comes from the live project list already parsed for check-in.

## README updates

The README already mentions the Keychain prompt for first run (Quick start) and the
Keychain technical reference (How it works). When building the Settings screen, also:

- Add a one-liner near the **Test connection** button / Settings section:
  *"The first Test connection may show the Keychain 'Chrome Safe Storage' prompt —
  click Always Allow."*
- Generalize the existing quick-start line from "On first run" to cover repeat
  prompts: *"The first time it reads your cookie (and after changing Chrome profile)
  macOS may show the Keychain 'Chrome Safe Storage' prompt — click Always Allow."*
- Document the **Open at login** toggle and the `/Applications` recommendation for
  reliable auto-start (see Launch-at-login note below).

## Tests / build

- No `BizneoCore` logic changes → existing `--selftest` stays green.
- Add a `Config` encode → decode round-trip check (guards the settings save path).
- Rebuild `BizneoCompanion.app`.

## Notes / risks

- **AppKit window from an agent app:** handled via `NSApp.activate` +
  `makeKeyAndOrderFront`; strong reference retained.
- **Launch-at-login reliability:** `SMAppService` registers the app at its current
  path. If the build lives in a cloud-synced folder, login items from such a path
  (spaces, sync delays) can be flaky. For dependable
  auto-start, move `BizneoCompanion.app` to `/Applications`. The toggle should work
  regardless; note this in the UI/README.
- **Test connection** uses the real cookie/Keychain path, so the first test may show
  the Keychain prompt — expected.
- All fields already exist in `Config` with a tolerant decoder, so older
  `config.json` files keep working.
