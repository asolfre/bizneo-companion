# Plan: `leaveByScope` — which backlog "Leave by" clears

> **This plan was rewritten mid-flight.** It began as *"configurable carryover
> scope"*: a `carryoverScope` setting that folded a period's backlog into the
> **menu-bar** number while `barMetric == .today`. That design was found to be a
> no-op before any code was written, and was replaced with the one below. The
> original is preserved in [Rejected design](#rejected-design-carryover-in-the-menu-bar)
> because the reasoning is the useful part.

## Concept

New config `leaveByScope` (`none`/`week`/`month`/`year`, default `none`) selects
which period's backlog the **Leave by** line clears.

- `none` (default) — unchanged behaviour: leave when *today's* target is met.
- `week`/`month`/`year` — leave when that period's balance reaches zero, i.e.
  when the accumulated deficit is paid off.

Nothing else changes. The menu-bar number, the dropdown rows and the year total
are all untouched.

## Why not the menu bar (rejected design)

### Rejected design: carryover in the menu bar

The original plan added `carryoverScope` and, when `barMetric == .today`, showed
`todayCarryover` in the bar — a copy of `today` with `officialBalanceMin` and
`pendingDeltaMin` taken from the scope's `PeriodStat`.

That produces **no observable change**, for three reasons that compose:

1. `config.barMetric` is read in exactly one place, `StatusItemController.swift`'s
   `barContent()`. Nothing else in the app branches on it — there is no
   active-row highlight in the dropdown.
2. `barContent()` turns a `PeriodStat` into output through only `barText(stat)`
   and `colorForSeconds(liveSeconds(stat))`. The icon comes from `s.barState`,
   which reads `today` regardless.
3. Both of those collapse the stat to `liveSeconds`, which is
   `projectedBalanceMin * 60 + elapsed`, and `projectedBalanceMin` is exactly
   `officialBalanceMin + pendingDeltaMin` — *the two fields the plan copied*.

`label`, `loggedMin` and `expectedMin` are never read on that path, so
`todayCarryover` and `stat(for: mapped)` are indistinguishable to every consumer
that exists. On the June fixture both routes give projected `-20` → `-0:20`, red:

| Setting | official | pending | projected | bar |
|---|---|---|---|---|
| `barMetric=.week`, carryover `.none` | -460 | +440 | -20 | `-0:20` |
| `barMetric=.today`, carryover `.week` | -460 | +440 | -20 | `-0:20` |

The original plan half-noticed this ("mathematically identical to the selected
timeframe's `PeriodStat`") but justified it as the value being *anchored/labeled
on Today*. The menu bar renders no label, only a number, and the same plan left
the dropdown rows raw — so the anchoring was invisible. The cost would have been
a permanent `Config` key, a `Snapshot` field, a `Calculator` function, client
wiring, a controller branch, tests in two files and a Settings row, for zero
user-visible effect.

**Leave by** is the one place a scope is *not* redundant: `barMetric` has no
influence over it at all.

## 1. `Config.swift`

- `public enum LeaveByScope: String, Codable { case none, week, month, year }`
- `public var leaveByScope: LeaveByScope`, default `.none`.
- Memberwise `init` parameter **and** a matching `decodeIfPresent` line in the
  hand-written `init(from:)` — the AGENTS.md gotcha. Here the compiler happens to
  catch an omission (the property is non-optional with no inline default), but
  that is luck, not a guarantee; see the round-trip test below.

## 2. `Calculator.swift`

```swift
public static func leaveByStat(_ snapshot: Snapshot, scope: LeaveByScope) -> PeriodStat
```

Maps scope → period, with `.year` falling back to `month` when the year total is
disabled, matching `Snapshot.stat(for:)`.

`expectedCheckout` needs **no math change** — only its argument label goes from
`today:` to `stat:`, because it is no longer only ever given today. The
"stays constant between refreshes" property still holds for every scope: week,
month and year all fold today's running session in via the reconcile step, so
they tick at the same rate as `today` and the same cancellation applies.

## 3. `TimeFmt.swift`

```swift
public static func clock(_ date: Date, since reference: Date, calendar: Calendar) -> String
```

`HH:MM`, suffixed `(+Nd)` when the result lands on a later calendar day. A
month-sized backlog can push the checkout past midnight, where a bare `01:00`
would read as an early-morning time *today* — the one day it certainly is not.

This lives in `TimeFmt`, not in the controller, so both test files can reach it.

## 4. `StatusItemController.swift`

`expectedCheckoutText()` resolves the stat via `Calculator.leaveByStat` and
formats with the day-aware `clock`. That is the whole UI change; the call site
that renders `🏁 Leave by …` is untouched.

## 5. No changes

`Models.swift` (no `todayCarryover` — the rejected design's field is not needed),
`BizneoClient` (no wiring at all), `barContent()`, the dropdown rows,
`TimesheetParser`, `computeYear`.

## Tests

In both `SelfTest.swift` and `ParserTests.swift`, per the AGENTS.md lockstep. At
the fixture's `now = Thu 18 Jun 2026 12:00`:

- scope → period mapping, including `.year` → month when `year == nil`.
- `.week` → **12:20** (projected -460+440 = -20), a genuinely different answer
  from `.none`'s 12:29 — the assertion that would have been impossible to write
  for the rejected design.
- `.month` → **nil**: projected -367+440 = +73, already ahead, so no time at all.
- `(+1d)` suffix on a 13h backlog, and its absence on a same-day time.
- `Config` encode→decode round-trip, plus decoding a legacy `config.json` that
  predates the field. These guard the `decodeIfPresent` line directly: dropping it
  fails `leaveByScope survives encode→decode`.

No fixture magic numbers move; all additions.

## Verify

```
BUILD_PATH=/tmp/bc swift run BizneoCompanion --selftest Tests/BizneoCompanionTests/Fixtures
```

Then set `"leaveByScope": "week"` in `config.json`, relaunch, and check the
**Leave by** line against the Today and This week rows.
