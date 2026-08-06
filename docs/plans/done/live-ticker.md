# Plan: Reconcile + Live Ticker

Goal: make `week` / `month` / `year` include today's currently-running timer (not
just `today`), and make the displayed numbers tick up smoothly between refreshes
while the timer is running.

## Background (root cause)

- `today` is built from the live chrono widget (`hub_chrono` → `loggedMin`), which
  **includes the currently-running session** (as of the last refresh).
- `week` / `month` / `year` are built from the **timesheet** (`my-logs`): they sum
  that page's day balances / "Until today" header, which only reflect **committed /
  saved** time. The in-progress running session isn't written there until you pause
  or check out.
- Result: while the timer runs, only `today` moves; `week` (the default bar metric)
  stays flat until the session is committed. The two sources are inconsistent.

## Decisions (confirmed)

- **Reconcile + live-tick** (smooth second-by-second).
- **Bar tick style:** config toggle `barShowSecondsWhileWorking`, **default `false`**
  → bar stays `H:MM` (per-minute, second-accurate underneath), dropdown lines show
  `H:MM:SS` while working. When `true`, the bar shows `H:MM:SS` ticking each second
  while clocked in.

## Part 1 — Reconcile (`Calculator.makeSnapshot`)

After `today`, `week`, `month` are computed, fold the live delta into the longer
periods:

```
committedToday = (todayRow.balanceMin ?? 0) + dayOffCorrection(todayRow)
liveDelta      = today.officialBalanceMin − committedToday   // running session not yet in timesheet
week.officialBalanceMin  += liveDelta
month.officialBalanceMin += liveDelta
```

- Apply only when `hubChrono != nil`.
- `year` inherits it automatically (built from `snapshot.month` in
  `BizneoClient.computeYear`).
- Safe both ways: if the timesheet already counts the session, `liveDelta ≈ 0`
  (no change); otherwise week/month/year now match `today`.
- No double-count with live-tick: the snapshot delta is "up to last refresh";
  live-tick only adds time *since* the refresh.

## Part 2 — Live-tick (`StatusItemController`, display-only)

- Track `lastRefreshAt = snapshot.generatedAt`.
- A **1-second `displayTimer`** scheduled in **`.common` run-loop mode** so it keeps
  firing while the menu is open. Runs **only while `status == .working`**.
- Pure, testable helper:
  ```
  liveSeconds(stat) = stat.projectedBalanceMin*60 + (isWorking ? elapsedSinceRefresh : 0)
  ```
  applied uniformly to today/week/month/year (all include today's session).
- Each tick: update the bar title; if the menu is open, update the stored
  period-item titles **in place** (keep references; do not rebuild the whole menu
  each second).
- Reset baseline on every real refresh; freeze on `paused` / `stopped` / error.
- Bar format honors `barShowSecondsWhileWorking`; dropdown period lines show
  `H:MM:SS` while working.

## Part 3 — Supporting changes

- `TimeFmt.signedHMS(_ seconds:)` → `−7:46:30`.
- Config: add `liveTick: Bool = true` (master on/off) and
  `barShowSecondsWhileWorking: Bool = false`; update the tolerant decoder.

## Tests / build

- Add `TimeFmt.signedHMS` unit test and a pure `liveSeconds` test.
- Update week/month/year self-test expectations for the reconcile delta
  (`hub` today vs `my-logs` today = +2:14 / 134 min in the fixtures).
- Rebuild BizneoCompanion.app.

## Status

- IMPLEMENTED and committed ("Add live ticker for balance"). Followed by
  "Ticker only for today" (seconds only on the Today row); now being made
  configurable via `plan_configurable_seconds.md`.

## Known limitation (inherent to live-tick without faster refresh)

- If a break is taken between refreshes, the ticker keeps counting until the next
  refresh corrects it (self-heals within `refreshSeconds`).
