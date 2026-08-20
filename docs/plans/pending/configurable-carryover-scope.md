# Plan: `carryoverScope` for the menu-bar Today figure

## Concept

New independent config `carryoverScope` (`none`/`week`/`month`/`year`). When set and
the menu bar is showing **Today** (`barMetric == .today`), the bar number folds in the
selected timeframe's full backlog (exposed as `todayCarryover`). The dropdown rows stay
raw (Today shows today, Week shows week, etc.). Fully orthogonal to `barMetric`.

Interaction summary:

- `barMetric == .today` + `carryoverScope == .month` → bar shows the month-adjusted Today number.
- `barMetric == .week` + any `carryoverScope` → bar shows raw week (carryover ignored).

Note: `full` carryover is mathematically identical to the selected timeframe's
`PeriodStat` (the week/month/year balances already fold today's live delta in via the
reconcile step in `Calculator.swift`). What's new is that the value is anchored/labeled
on **Today** and decoupled from `barMetric`.

## 1. `Config.swift`

- Add enum near `BarMetric`:
  ```swift
  public enum CarryoverScope: String, Codable { case none, week, month, year }
  ```
- Add stored field `carryoverScope: CarryoverScope = .none` (default preserves current behavior).
- Add it to the memberwise `init(...)`.
- **AGENTS.md gotcha:** add a matching `decodeIfPresent` line in the custom `init(from:)`
  (`Config.swift:82-101`), else old `config.json` silently drops it.

## 2. `Models.swift`

- Add `public var todayCarryover: PeriodStat?` to `Snapshot` (default `nil`; set
  post-computation). Keeping the raw `today` untouched avoids breaking the reconcile math
  and the `snap.today.officialBalanceMin == 451-480` self-test.

## 3. `Calculator.swift` — new `applyCarryover`

Runs *after* year is computed so `.year` scope works:

```swift
public static func applyCarryover(to snapshot: inout Snapshot, config: Config)
```

- `guard config.carryoverScope != .none else { return }`
- Map scope→`BarMetric` and get `scopeStat = snapshot.stat(for: mapped)` (already returns
  `year ?? month`, so it's safe when `enableYearTotal == false`).
- Build `snapshot.todayCarryover` = copy of `today` with `officialBalanceMin` and
  `pendingDeltaMin` from `scopeStat`. Label kept "Today".

No date math, no approximations.

## 4. `BizneoClient.swift` — wire it in

In `refresh()` (~line 150), after the `computeYear` block that sets `snapshot.year`, add:

```swift
Calculator.applyCarryover(to: &snapshot, config: config)
```

`snapshot` is already a `var`. No other client changes.

## 5. `StatusItemController.swift` — menu bar only

- There is a single bar-title path: `barContent()` (`StatusItemController.swift:187`),
  which reads `s.stat(for: config.barMetric)` at line **196**. Change it so that when
  `barMetric == .today` **and** `carryoverScope != .none` it uses
  `s.todayCarryover ?? s.today` instead. (The two separate title paths this plan was
  first written against were collapsed into `barContent()` by the menu-bar clock-states
  work — see `docs/plans/done/menu-bar-clock-states.md`.)
- **Do not touch the early return above it** (`:193`): when
  `state.needsAttention && config.enableClockActions`, `barContent()` replaces the
  balance with `"Check in"` and never reads a `PeriodStat`. Carryover must apply only
  to the fall-through path — folding a backlog into the one state whose purpose is to
  hide the number would defeat it.
- Everything else (dropdown `rebuildMenu`, `periodItem` rows) is unchanged — Today/Week/
  Month/Year rows stay raw.
- Live-tick on the bar works unchanged (`todayCarryover` is a normal `PeriodStat`).

## 6. Tests — update magic numbers (both files, per AGENTS.md)

Add assertions to `SelfTest.swift` **and** `Tests/BizneoCompanionTests/ParserTests.swift`
at the fixture's `now = Thu 18 Jun 2026`:

- `carryoverScope == .week` → `todayCarryover.official == -460` (== week.official).
- `carryoverScope == .month` → `todayCarryover.official == -367` (== month.official).
- `carryoverScope == .none` → `todayCarryover == nil`.

## 7. No changes

Dropdown UI, settings UI (JSON-file config, consistent with `barMetric`),
`TimesheetParser`, `TimeFmt`, `computeYear`.

## Verify

```
BUILD_PATH=/tmp/bc swift run BizneoCompanion --selftest Tests/BizneoCompanionTests/Fixtures
```
