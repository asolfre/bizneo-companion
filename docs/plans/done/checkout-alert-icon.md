# Plan: Proper icons on the clock alerts

**Goal:** Both `NSAlert` dialogs currently render the generic blank executable
icon. Give them meaningful, tinted SF Symbols without adding any image assets to
the repo.

**Decisions:**
- Use **SF Symbols** (`NSImage(systemSymbolName:)`), not a bundled icon file —
  nothing to ship, no `resources:` in `Package.swift`, no `Bundle.module`.
- Check-out confirmation: **`figure.walk.departure`**, hierarchical
  **`.systemOrange`**.
- Clock-failure alert: **`exclamationmark.triangle.fill`**, hierarchical
  **`.systemRed`**, via the same helper.
- A real `AppIcon.icns` for the bundle is **out of scope** (see Notes).

## Current state
- `checkOut()` (`StatusItemController.swift:357`) and the failure alert inside
  `doClock(_:)` (`StatusItemController.swift:380`) are the app's only two
  `NSAlert`s. Neither sets `alert.icon`, so AppKit falls back to
  `NSApp.applicationIconImage`.
- The bundle has no icon: `build_app.sh:16` creates an empty
  `Contents/Resources/`, and the generated `Info.plist` (`build_app.sh:19-36`)
  declares neither `CFBundleIconFile` nor `CFBundleIconName`. Result: a generic
  blank-document icon in both dialogs.
- `alert.alertStyle = .warning` (`StatusItemController.swift:363`) has no visual
  effect on modern macOS; only `.critical` changes anything, by badging the app
  icon with a caution triangle.
- The app uses **zero** image APIs today — no `NSImage`, no `NSMenuItem.image`,
  no asset catalog. Every glyph is an emoji inside a title string
  (`clockGlyph`, `StatusItemController.swift:128`).

## 1. `StatusItemController.swift` — new `// MARK: - Alerts` helper
Insert immediately above `checkOut()` (currently line 357):
```swift
// MARK: - Alerts

/// A tinted SF Symbol sized for an NSAlert's 64pt icon well.
/// Returns nil when the symbol is unavailable, in which case the caller leaves
/// `alert.icon` untouched and AppKit keeps its default.
private func alertIcon(_ name: String, color: NSColor) -> NSImage? {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
    let cfg = NSImage.SymbolConfiguration(pointSize: 48, weight: .regular)
        .applying(NSImage.SymbolConfiguration(hierarchicalColor: color))
    let img = base.withSymbolConfiguration(cfg)
    img?.isTemplate = false   // keep the tint; symbol images default to template
    return img
}
```
Three details that matter:
- **`isTemplate = false` is mandatory.** Images from `systemSymbolName:` come
  back with `isTemplate == true`; AppKit would re-render them flat black/white
  and silently discard the hierarchical tint.
- `hierarchicalColor:` and `.applying(_:)` are macOS 12+,
  `withSymbolConfiguration(_:)` is macOS 11+. Deployment target is macOS 13
  (`Package.swift:6`), so no `@available` guards are needed.
- `pointSize: 48` sits inside NSAlert's ~64pt icon well with sane optical
  margin; nudge 44–56 if it looks small or crowded.

## 2. `StatusItemController.swift` — check-out confirmation
One added line in `checkOut()`, after `alert.alertStyle`:
```swift
alert.alertStyle = .warning
if let icon = alertIcon("figure.walk.departure", color: .systemOrange) { alert.icon = icon }
```
Keep `.warning` — it documents intent and costs nothing. Do **not** switch to
`.critical`: that composites a caution badge over the custom icon and overstates
an action that is reversible by simply checking in again.

## 3. `StatusItemController.swift` — clock-failure alert
In the `catch` block of `doClock(_:)` (lines 380-383):
```swift
alert.alertStyle = .critical
if let icon = alertIcon("exclamationmark.triangle.fill", color: .systemRed) { alert.icon = icon }
```
Colour note: the menu-bar error state already uses `.systemOrange`
(`applyError()`, line 140, and the `⚠︎` row at line 194). Red is chosen here to
separate a hard failure from the orange "deliberate action" check-out icon;
switching to `.systemOrange` for app-wide consistency is a one-word change.

## Verify
- `BUILD_PATH=/tmp/bc swift build` — compiles.
- `BUILD_PATH=/tmp/bc swift run BizneoCompanion --selftest Tests/BizneoCompanionTests/Fixtures`
  -> ALL PASSED. Presentation-only change: no parser, no `Calculator`, no
  `Config` field, so none of the hardcoded fixture numbers (`-861`, `+134`,
  `+360`) move and no `decodeIfPresent` line is required.
- `./build_app.sh && open BizneoCompanion.app` -> while clocked in, choose
  **Check out…** and confirm the walking-figure glyph renders orange, crisp and
  well-sized in **both Light and Dark mode**. Cancel out.
- The failure alert is hard to trigger deliberately; dropping the network before
  a clock action is the easiest route, otherwise it shares the code path already
  exercised above.

## Status

- IMPLEMENTED as specified — `alertIcon` helper (`StatusItemController.swift:357`),
  check-out icon (line 378), failure icon + `.critical` (lines 398-399). 18 added
  lines, one file; no other file touched.
- Verified on macOS 14.6: build clean, `--selftest` ALL PASSED (no fixture numbers
  moved), both symbols resolve (59×60 and 60×52 at `pointSize: 48`, so no size
  tweak needed), and pixel-sampling the rendered images confirms the tint survives
  — orange `rgb(255,175,1)` / red `rgb(255,94,73)`, not flat black, so
  `isTemplate = false` is doing its job. An unknown symbol name returns nil, so the
  `if let` fallback is exercised and cannot regress.

## Notes / heads-up
- **Cannot regress.** `NSImage(systemSymbolName:)` returns an Optional and never
  throws; if a symbol were ever missing, the `if let` skips the assignment and
  behaviour is identical to today. Nothing else in the app reads `alert.icon`.
- Scope is one file, ~15 added lines. `Package.swift`, `build_app.sh`,
  `Info.plist`, `Config.swift`, `SelfTest.swift` and `ParserTests.swift` are all
  untouched.
- **Deliberately out of scope:** a real `AppIcon.icns`. It would brand every
  dialog (and any future window from `pending/add-settings-screen.md`) rather
  than these two, but needs actual artwork plus `build_app.sh`, `Info.plist` and
  `NSApp.applicationIconImage` changes. Worth a separate plan if wanted.
- This is the first use of `NSImage` anywhere in the codebase; `alertIcon` is the
  natural choke point if per-menu-item images are ever added (the
  `header`/`info`/`actionItem` factories at lines 318-339 set no `.image`).
