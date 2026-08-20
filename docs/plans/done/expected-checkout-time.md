# Expected checkout time ("Leave by")

> **This plan was reconstructed after the fact.** The feature was designed in a
> planning session and implemented straight from it, before `docs/plans/` existed, so
> no file was ever written — which is why the Done table had four rows for five
> shipped features. The design below is the one that was actually agreed and built;
> *What changed after the plan* records where the shipped code diverged. Unlike every
> other file here, it did not guide the implementation.

## Goal

Answer the question the balance figure implies but never states: **what time can I
leave today?** The menu already shows how much you are missing; this turns that
duration into a wall-clock time.

## Key insight: the value is constant between refreshes

The Today balance ticks live — `liveSeconds(today) = projectedBalanceMin*60 +
elapsedSinceRefresh`. The checkout target is the moment that reaches zero, and solving
for it cancels the two moving terms:

```
checkoutAt = generatedAt + max(0, -projectedBalanceMin) minutes
```

`+now` and `−elapsedSinceRefresh` cancel back to the snapshot's own timestamp, so the
result **does not move between refreshes** even while the balance ticks. That is what
makes this cheap: it is computed once in `rebuildMenu` and needs no `periodRows` entry
and no work in `tick()`. It only changes when a new snapshot arrives.

Anchoring on the snapshot rather than on `Date()` is also what keeps the row honest
during a break: the timer is frozen, so a `now`-based estimate would drift later every
second while you are away from the desk.

## Design

### 1. `Calculator.expectedCheckout(today:generatedAt:)` — `Calculator.swift:47`

```swift
public static func expectedCheckout(today: PeriodStat, generatedAt: Date) -> Date? {
    let owedMin = -today.projectedBalanceMin
    guard owedMin > 0 else { return nil }
    return generatedAt.addingTimeInterval(Double(owedMin) * 60)
}
```

Pure and additive — it derives from an existing figure and changes no existing math,
so none of the hardcoded fixture numbers move. `nil` when the target is already met,
which is what hides the row rather than a separate flag.

### 2. `TimeFmt.clock(_:calendar:)` — `TimeFmt.swift:64`

Formats an absolute `Date` as `HH:MM` in the calendar's timezone. It lives in
`BizneoCore` **specifically so `--selftest` can cover it** — the controller's private
`clockTime` (`StatusItemController.swift:552`) is unreachable from the self-test.

### 3. Render in the `.working` clock section — `StatusItemController.swift:411-412`

```swift
if let leaveBy = expectedCheckoutText() {
    menu.addItem(info("\(Glyph.leaveBy) Leave by \(leaveBy)"))
}
```

`expectedCheckoutText()` (`:563`) reads `latest`, feeds `s.today` and `s.generatedAt`
to the calculator, and formats through a Madrid `Calendar` from
`Calculator.madridCalendar(weekStartsMonday:)`. Built in `rebuildMenu`, never ticked.

### 4. Coverage

Four assertions in `SelfTest.swift:107-119`, mirrored in `ParserTests` per AGENTS.md's
lockstep rule.

## Decisions

- **Only while working.** Not on break, not when stopped. A frozen timer would leave a
  stale time on screen that looks authoritative.
- **Projected balance, not official.** So the row agrees with the "missing" figure on
  the Today row, and inherits `includePending` gating from `makeSnapshot` for free.
  Using the official balance would put two contradictory numbers in the same menu.
- **Always on, no `Config` field.** One less setting, and — per AGENTS.md — no
  `decodeIfPresent` line to forget in the custom `init(from:)`.

## Rejected

- **Ticking the row every second.** Provably pointless: the value is constant between
  refreshes (see above). Re-rendering it each second would only add flicker.
- **A config flag to disable it.** The row already hides itself in the only case where
  it is meaningless — when you are at or over target.

## Verification

```
swift run BizneoCompanion --selftest Tests/BizneoCompanionTests/Fixtures
```

At the fixture's `now = 12:00` with Today 0:29 behind:

- `expectedCheckout == now + 0:29`, formatting to `"12:29"`.
- A non-negative balance → `nil`, so no row.
- The formatter renders a known date as `"16:28"`.

No `Calculator` or `TimesheetParser` math changed and no `Config` field was added, so
the month `-861`, reconcile `+134` and day-off `+360` assertions were untouched.

## What changed after the plan

- **The anchor moved.** The plan computed from the controller's `lastRefreshAt`; the
  shipped `expectedCheckoutText()` uses the snapshot's own `generatedAt`. Same
  instant in practice, but it keeps the whole calculation inside data the self-test
  can construct, instead of controller state it cannot.
- **It was written against one base and landed on another.** The plan was drafted
  against the live-ticker working tree, implemented on a branch cut from a `main` that
  predated live-ticker, then rebased once live-ticker merged. The assertions survived
  the rebase because they key off `snap.today` (`451-480 = -29`), and the live-ticker
  reconcile delta only moves week/month/year. **That is why these checks read `today`
  and not a longer period** — a reconcile-affected figure would make them fragile.
- **A lockstep regression was caught in review.** The first commit deleted the
  `week pendingDeltaMin` assertion from `SelfTest.swift` while `ParserTests` kept the
  equivalent check, breaking the parity AGENTS.md requires. Restored in `92ccf2f`;
  it is the check now at `SelfTest.swift:105`.
- **The glyph later moved.** `🏁` shipped as a string literal at the call site; the
  menu-bar clock-states work folded it into the `Glyph` table
  (`StatusItemController.swift:370`) along with the other duplicated literals.
