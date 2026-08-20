# State-aware menu-bar icons

Make the menu bar say *what the clock is doing*, so a forgotten check-in is
impossible to miss.

## Problem

Every "icon" today is an emoji prefixed to the title string (`clockGlyph`,
`StatusItemController.swift:127`); `statusItem.button?.image` is never used. The
mapping is:

| State | Bar renders | Colour |
|---|---|---|
| Working | `● -0:29` | red/green by **balance sign** |
| On break | `⏸ -0:29` | same, frozen (no tick) |
| Not checked in | `-0:29` — **no glyph** | same |
| Checked out for the day | `-0:29` — **identical to above** | same |
| `.unknown` (parser broke) | `-0:29` — also identical | same |
| Error | `⚠︎` | orange |
| Loading | `⏳` | dim |

Seven UX problems:

1. **The most important state has the weakest signal.** "Not checked in" is encoded
   as the *absence* of a mark, and absence is invisible.
2. **"Not checked in yet" and "done, checked out" are pixel-identical.**
   `ChronoStatus` (`Models.swift:148`) has no `checkedOut` case — Bizneo returns the
   same start form before the first check-in and after checkout, so both collapse
   into `.stopped`.
3. **Colour never encodes clock state, only the balance sign** (`colorForSeconds`,
   `StatusItemController.swift:87`). At 10:00 with a green `+2:11` week balance and
   the clock stopped, the bar looks *reassuring* — the worst possible failure mode.
4. **The number follows `barMetric` (default `week`)**, so a good week masks a
   forgotten check-in today.
5. **`.unknown` degrades silently** to look exactly like `.stopped`: it hits
   `clockGlyph`'s `default:` and is filtered out of the menu at
   `StatusItemController.swift:173`, so a Bizneo markup change is undiagnosable.
6. `enableClockActions: false` suppresses the glyph entirely
   (`StatusItemController.swift:129`) — but "your timer isn't running" matters even
   when you clock in from the browser.
7. `●` reads as a bullet, not "recording". Emoji also render at an inconsistent
   weight/baseline against the monospaced digits and ignore menu-bar tinting.

## Design

### 1. `BarState` — `Sources/BizneoCore/BarState.swift`

Because Bizneo has no "checked out" state, it is *inferred* from `today`. Pure
function, no I/O, therefore fully covered by `--selftest`:

```swift
public enum BarState: String, Equatable {
    case working, onBreak, notCheckedIn, checkedOutEarly, doneForToday, offDuty, unknown
}

public static func derive(chrono: ChronoStatus?, today: PeriodStat) -> BarState
```

```
working → .working ; paused → .onBreak ; nil / .unknown → .unknown
stopped:
  today.expectedMin         <= 0 → .offDuty          // weekend / holiday / day off
  today.projectedBalanceMin >= 0 → .doneForToday     // target met, clock legitimately off
  today.loggedMin            > 0 → .checkedOutEarly  // deliberate early stop
  else                           → .notCheckedIn     // the one you are missing
```

Plus a `Snapshot.barState` convenience.

- Uses `projectedBalanceMin` so the state agrees with the "missing" figure on the
  Today row and with `Calculator.expectedCheckout` (`Calculator.swift:47`).
- `offDuty` leans on `Calculator.swift:97`, which already forces
  `today.expectedMin = 0` for day-off schedules; on weekends/holidays `hub_chrono`
  reports 0 scheduled minutes, and if both `hubChrono` and the day row are missing
  `today` stays all-zeros — which lands on `offDuty`, the quiet default. Verified
  manually (see *Verification*).
- **State is derived from `snapshot.today` regardless of `config.barMetric`.** The
  number keeps following `barMetric`; today's problem can no longer hide behind a
  green weekly aggregate.

### 2. Icon table

| State | SF Symbol | Rendering | Bar text |
|---|---|---|---|
| `working` | `play.circle.fill` | template | balance, ticking |
| `onBreak` | `pause.circle.fill` | template | balance, frozen |
| **`notCheckedIn`** | `clock.badge.exclamationmark` | **`systemOrange`, non-template** | **`Check in`**, orange |
| `checkedOutEarly` | `stop.circle` | template, dimmed | balance |
| `doneForToday` | `checkmark.circle` | template, dimmed | balance |
| `offDuty` | *none* (`image = nil`) | — | balance, dimmed |
| `unknown` | `questionmark.circle` | template, dimmed | balance |
| error | `exclamationmark.triangle.fill` | orange | *(icon only)* |
| loading | `hourglass` | dimmed | *(icon only)* |

The icon carries the clock state; the text keeps carrying the balance sign in
red/green. Orange appears in the bar **only** when action is required, so it never
competes with the balance colour.

`notCheckedIn` is the only state that changes the item's *shape* rather than merely
adding a mark, which is what stops it being tuned out.

### 3. Rendering

`setTitle` (`StatusItemController.swift:151`) becomes `setStatus`, driving both the
image and the title:

- `button.image` + `imagePosition = .imageLeading`; **`image = nil`** on `offDuty`
  and on the icon-less path, or a stale icon persists.
- `SymbolConfiguration(pointSize: 12, weight: .semibold)` to sit correctly next to
  the 13pt semibold monospaced-digit title.
- `isTemplate = true` for every monochrome state, so icons follow menu-bar tint,
  dark mode and "reduce transparency". This is the *opposite* of `alertIcon`
  (`StatusItemController.swift:359`), which deliberately sets `false` to keep its
  tint in an `NSAlert` icon well — reuse its structure, not its flag.
- `accessibilityDescription` on the image and a `toolTip` on the button, per state;
  VoiceOver currently reads nothing.
- The in-flight refresh (`StatusItemController.swift:47`) dims the text only and
  keeps the icon, avoiding a flicker every 10 minutes.
- If `NSImage(systemSymbolName:)` returns nil the state falls back to its emoji
  glyph, the same defensive pattern `alertIcon` uses.

### 4. `enableClockActions`

Today the flag suppresses the glyph entirely. From now on **state icons always
render** — `chrono` is parsed unconditionally (`BizneoClient.swift:130`) — and the
flag keeps gating only the menu *actions*. When it is `false`, `notCheckedIn` still
shows the orange icon but keeps the balance text instead of the word `Check in`, so
the bar never offers an action the app will not perform.

`isWorking` (`StatusItemController.swift:72`) is ungated for the same reason: the
Bizneo timer runs, and the balance grows, whether or not this app may stop it, so
the live tick should follow the timer rather than the permission flag.

### 5. Dropdown

Glyphs were duplicated string literals (`StatusItemController.swift:225`, `:267`,
`:275`, `:279`); they move to one table. The stopped section becomes state-aware:

- `notCheckedIn` → `⚠︎ Not clocked in · missing 8:00 today`
- `checkedOutEarly` → `○ Checked out · logged 6:40, missing 1:20`
- `doneForToday` → `✓ Checked out · today complete`
- `offDuty` → `○ No hours expected today`

Check-in items are unchanged in all four. A `? Clock state unknown` row is added for
`.unknown`, which is currently filtered out of the menu entirely and therefore
impossible to diagnose.

## Rejected

- **Quiet hours / `workdayStartsAt` config** — a new `Config` field for a heuristic
  that still guesses. Showing "check in" from 07:30 is *correct*: you do owe hours
  and the clock is not running.
- **Inferring the start hour from the Bizneo schedule range** (`08:00-16:00` →
  08:00): false alarms for anyone who flexes their start.
- **A pulsing/animated icon** — obnoxious by macOS convention.
- **A local notification** — needs `UNUserNotificationCenter`, a permission prompt
  and the bundled `.app`. Worth a separate plan if the static orange proves too
  quiet in practice.

## Verification

- `swift run BizneoCompanion --selftest Tests/BizneoCompanionTests/Fixtures` — a
  `bar state:` block driving `derive()` with the three `chrono_*.html` fixtures ×
  synthetic `PeriodStat`s, including the case that motivates the whole feature: a
  green weekly total must not suppress the warning. Mirrored in `ParserTests` as
  `testBarState` / `testBarStateIgnoresBarMetric`.
- **No `Calculator` or `TimesheetParser` changes**, so none of the hardcoded fixture
  numbers move. **No new `Config` field**, so no `decodeIfPresent` hazard. Both are
  deliberate properties of this design.
- Manual matrix (cannot be fixtured): before the first check-in → working → break →
  checked out with the target met → checked out early → a weekend (the
  `expectedMin == 0` assumption) → a company day off. Plus light/dark menu bar and
  "Reduce transparency".

## Known limitation

Dimmed states (`checkedOutEarly`, `doneForToday`, `unknown`) fade the *text* only;
the icon stays a full-strength template image. Applying alpha would mean
hand-drawing the symbol into a new `NSImage`, which loses the automatic menu-bar
appearance handling that templating buys. Not worth it for the contrast gained.
