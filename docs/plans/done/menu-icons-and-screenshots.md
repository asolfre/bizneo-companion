# Plan: Menu icons that match the bar, `--demo`, README screenshots

*Planned in conversation and implemented in the same branch; no pending stage.*

## Problem

- **The dropdown spoke a different visual language from the bar.** The bar has used
  SF Symbols since `menu-bar-clock-states.md` (`look(for:)`), but the menu still
  prefixed emoji to its titles (`Glyph`). The same 🟢 meant both "ahead" (period
  rows) and "Working" (clock row), the Leave by row had a 🏁, and ⚠︎ / ○ / ✓ were
  text glyphs that sat at a different weight from the icons above them.
- **The README had no real images**, only an ASCII sketch of the menu and a TODO.
  Taking real screenshots meant real data (balances, project names) and waiting
  for each clock state to happen. A break or check-out done only for a screenshot
  ends up in the real timesheet.

## 1. Menu icons

Every clock row now uses `NSMenuItem.image` with the bar's own icon, through a new
`icon(_ look:)`. It reuses `barIcon`, so the symbol, tint and accessibility label
all come from `look(for:)`, and the menu and the bar can't drift apart.

| Row | Was | Now |
|---|---|---|
| Working · since | 🟢 | `play.circle.fill`, `look(.working)` |
| On break | ⏸ | `pause.circle.fill`, `look(.onBreak)` |
| Not clocked in | ⚠︎ | `clock.badge.exclamationmark`, orange |
| Checked out early | ○ | `stop.circle` |
| Today complete | ✓ | `checkmark.circle` |
| No hours expected | ○ | none: the bar shows none either |
| Clock state unknown | ? | `questionmark.circle` |
| Leave by | 🏁 | `figure.walk.departure`, the check-out alert's figure |
| Error row | ⚠︎ | `exclamationmark.triangle.fill`, orange (`BarLook.error`) |
| Loading… | none | `hourglass` (`BarLook.loading`) |
| Check in · project, Check in ▸, Resume | none | `play.circle.fill` |
| Take break | none | `pause.circle.fill` |
| Check out… | none | `stop.circle` |

- **An action shows the icon of the state it leads to.** **Check out…** gets
  `stop.circle`, not the walking figure: Leave by sits right above it, so two
  figures would stack.
- **Period rows show a dot and a coloured balance.** The image is `circle.fill`,
  tinted red or green with `colorForSeconds`, or a template `circle` when the
  balance is level. The attributed title colours only the "missing 0:29" /
  "ahead 2:11" part.
  - `stylePeriod` replaces `periodTitleString` and also runs on every tick,
    because the sign can flip while the timer runs.
  - The attributed title needs an explicit `menuFont(ofSize: 0)` and `labelColor`.
    Without them it falls back to Helvetica 12, and to black even in dark mode.
- **Which period-row style:** three versions were captured from `--demo`: dot only,
  coloured text only, and both. The user picked both. When a row is highlighted,
  the red text sits on the blue highlight at lower contrast. That was accepted.
- **No emoji fallback** for the menu: every symbol exists on macOS 13, the
  deployment target. If one were missing, the row would show no icon, and its text
  still reads fine.
- **Deleted:** the `Glyph` enum, now unused.

**AppKit behaviour seen on macOS 27:**
- Disabled rows fade their icons, and the orange ones stay orange.
- AppKit adds its own gear icon to **Settings…**.
- Rows without an icon line up with the titles of rows that have one.

## 2. `--demo`

`Sources/BizneoCompanion/Demo.swift` draws the real menu from the anonymized
fixtures, as of 18 Jun 2026 12:00 like `SelfTest`, plus its two made-up pending
requests and a made-up "This year" figure.

- **Command:** `swift run BizneoCompanion --demo <state>`, from the repo root.
- **States:** `working`, `break`, `not-checked-in`, `checked-out`, `done`, `off`,
  `unknown`. Each is one override on `today` or `chrono`.
- **Clock:** the snapshot is timestamped with the real time, so the live tick and
  "Leave by" run normally. `startedAt` is set 2.5 h back, so "since" comes before
  "Leave by".

**Isolation.** `Demo.isActive` is a `static let` read from the arguments, so there
was nothing to thread through the classes.

| Area | In demo mode |
|---|---|
| Startup | `start(demo:)` shows the snapshot and returns: no refresh timer, no fetch, no reminders. Slack sync stays off because `Demo.config` is `Config()` with placeholder `acme` / `123456`. |
| `refresh()` | Does nothing. |
| `doClock` | Applies `Demo.perform` in memory. The check-out confirmation still shows. |
| `lastProjectId` | Neither read nor written. A demo pick of a fixture project could otherwise become the real app's quick check-in. |
| Settings | Reads neither Chrome profiles nor the Keychain. **Test connection** does nothing, and **Save** only closes the window. **Without that guard, Save would write the placeholder config over the real `config.json`.** |

**Check:** `--selftest` gained a `demo mode:` block.
- Each state gives the matching `BarState`.
- An unknown state gives nil.
- Check in → Take break → Resume → Check out gives back `.notCheckedIn`, which is
  what lets the GIF loop.

## 3. Screenshots

`docs/screenshots.swift` (`swift docs/screenshots.swift`) regenerates every README
image. `docs/README.md` lists the files.

- **No keystrokes.** The demo is driven through Accessibility: click the status
  item, set `AXSelected` to highlight a row, `AXCancel` to close the menu. A global
  keystroke goes to whichever app is frontmost.
- **Windows are captured by id** (`screencapture -l`), so neighbouring menu-bar
  items and whatever is on screen never get in.
- **Menus are glass.** Captured alone, a light menu has nothing to blur and comes
  out flat grey (measured 0.53, where real light menus are near-white). So menus are
  shot over a plain borderless window in GitHub's page colour (white / `#0d1117`),
  at window level 30. That covers the menu bar but stays under menus (101); for the
  alert (8) the window goes at level 7.
- **The status item has no window:** the Window Server draws it into the menu bar,
  so it's captured as a screen rectangle.
  - The menu bar follows the wallpaper, not the appearance, so light and dark
    captures came out byte-identical: one `checkin-bar.png`.
  - In the GIF, the item's edge columns are stretched across the frame, which
    turns the wallpaper scrap back into a menu bar. The canvas is rounded to whole
    pixels, otherwise white seams show where the strip meets the item.
- **README:** PNGs in light/dark pairs inside `<picture>`, with each width in
  points, so a 2x re-shoot fits without edits.
- **GIF:** `demo.gif` is a 10-frame storyboard (Check in → break → resume → check
  out → confirm → back to Check in), composed at 1x on white and written with
  ImageIO. It's 110 KB, with no ffmpeg.

## Rejected design

- **Screen recording + ffmpeg for the GIF** (the first plan). It needs `brew install
  ffmpeg`, records whatever is behind the menu, and the confirmation dialog opens
  mid-screen, outside any sensible crop. Composed stills avoid all three.
- **Screen-region crops** (the first plan, `screencapture -R`). Trying them showed
  neighbouring status items and the user's own windows, folder names included,
  next to the menu.
- **Capturing from the real app** (an option in planning). The shots would show
  real balances and the real project picker, and each state could only be captured
  while it was happening.
- **Updating the ASCII sketch** in the README (the first icons plan). The
  screenshots replace it.
- **A dark copy of the GIF.** It's the heaviest file, and the light one works on
  both themes as a framed image.

## Verification

- `swift build`, `swift test`, `--selftest` (ALL PASSED, new `demo mode:` block)
  and `./build_app.sh` all pass.
- **No change to `Calculator`, the parsers or `Config`,** so no fixture numbers
  moved and no `decodeIfPresent` line was needed.
- **Every `--demo` state was captured and checked by eye on macOS 27.** The full
  clock loop was run through the menu, confirmation included. Clicking Settings →
  Save left `config.json` unchanged (same mtime and md5).
- **Known limits:**
  - The images in this branch were captured on a non-Retina display (1x), so
    they're slightly soft on Retina screens. Re-running the script with the menu
    bar on a Retina display gives 2x without README edits.
  - The menu header and Settings footer show `v…+dev`: the demo runs unbundled.
