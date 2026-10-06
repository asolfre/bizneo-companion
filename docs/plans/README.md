# Feature plans

Design docs for Bizneo Companion features. Each plan is written before the code and
kept afterwards as a record of *why* something works the way it does.

- **`pending/`** — designed, not implemented yet.
- **`done/`** — shipped. Kept as an archive, never deleted.

When a plan ships, move it in the same PR that implements it and update the tables
below:

```
git mv docs/plans/pending/<name>.md docs/plans/done/
```

If a plan is **abandoned or superseded before it ships**, don't just delete it: fold
it into its successor's plan as a `## Rejected design` section explaining what it
proposed and why it was dropped, then remove the original file in the same PR. The
reasoning is the valuable part — losing it invites someone to re-propose the same
dead end. `done/leave-by-scope.md` is the worked example (it absorbed
`configurable-carryover-scope.md`, which turned out to be a no-op).

## Pending

| # | Plan | Summary |
|---|---|---|
| 1 | [`pending/settings-connection-helpers.md`](pending/settings-connection-helpers.md) | The two Account-section helpers cut from the Settings window: Chrome-profile auto-detect and Test connection. |

## Done

| Plan | Shipped in |
|---|---|
| [`done/live-ticker.md`](done/live-ticker.md) | [PR #2](https://github.com/asolfre/bizneo-companion/pull/2) — reconcile today's running timer into week/month/year + smooth live tick |
| [`done/configurable-seconds.md`](done/configurable-seconds.md) | [PR #2](https://github.com/asolfre/bizneo-companion/pull/2) — `Config.dropdownSecondsScope` (`none`/`today`/`all`), default `today` |
| [`done/expected-checkout-time.md`](done/expected-checkout-time.md) | [PR #3](https://github.com/asolfre/bizneo-companion/pull/3) — `🏁 Leave by HH:MM` in the working clock section; `Calculator.expectedCheckout` + `TimeFmt.clock`. *Plan reconstructed after the fact.* |
| [`done/checkout-alert-icon.md`](done/checkout-alert-icon.md) | [PR #4](https://github.com/asolfre/bizneo-companion/pull/4) — tinted SF Symbols on both `NSAlert`s via a shared `alertIcon` helper; no bundled assets |
| [`done/menu-bar-clock-states.md`](done/menu-bar-clock-states.md) | [PR #6](https://github.com/asolfre/bizneo-companion/pull/6) — `BarState` splits Bizneo's single `.stopped` into not-checked-in / checked-out-early / done / off-duty; SF Symbol status icons, orange "Check in" warning |
| [`done/versioning.md`](done/versioning.md) | [PR #8](https://github.com/asolfre/bizneo-companion/pull/8) — `AppInfo` as the single source of truth, scraped by `build_app.sh` for the Info.plist; `--version` flag and version in the menu header. First tagged release, v0.1.0. |
| [`done/past-month-change-requests.md`](done/past-month-change-requests.md) | [PR #9](https://github.com/asolfre/bizneo-companion/pull/9) — `MonthTotal` retains each past month's requests so the "Pending changes" list stops emptying out after a month rollover; dedup/sort extracted to `Calculator.mergePending` to make it testable |
| [`done/leave-by-scope.md`](done/leave-by-scope.md) | [PR #10](https://github.com/asolfre/bizneo-companion/pull/10) — `Config.leaveByScope` picks which backlog the "Leave by" line clears, with a `(+Nd)` suffix when it spills past midnight. *Rewritten mid-flight: the original `carryoverScope` design targeted the menu bar and was a no-op — the plan records why.* |
| [`done/add-settings-screen.md`](done/add-settings-screen.md) | [PR #15](https://github.com/asolfre/bizneo-companion/pull/15) — SwiftUI Settings window (⌘,) replacing "Edit configuration…", covering all 17 `Config` fields plus `SMAppService` open-at-login; `applyConfig` reloads the client, timer and menu without a restart. *Shipped SwiftUI rather than the planned hand-built `NSGridView`, and deferred Chrome-profile auto-detect + Test connection to [`pending/settings-connection-helpers.md`](pending/settings-connection-helpers.md) — the plan records both.* |
| [`done/check-in-reminders.md`](done/check-in-reminders.md) | *unreleased* — branch `feature/check-in-reminders` ([#16](https://github.com/asolfre/bizneo-companion/issues/16)): notifications inside Madrid-time windows when not checked in, checked out early or on a break, with **Check in** / **Resume** / **Not today**; pure `Reminders.next` decision covered by `--selftest`. Every clock action, menu included, is now refused when Bizneo's fresh state doesn't allow it. *Seven review findings folded in before code — the plan records them.* |
| [`done/dev-build-version.md`](done/dev-build-version.md) | *unreleased* — branch `feature/check-in-reminders`: `build_app.sh` stamps a `BCBuild` key from git, so non-release builds show `0.3.0+<commit>` (`.dirty` with uncommitted changes) in `--version`, the menu header and Settings; `CFBundleVersion` becomes the commit count. *Written and shipped in the same commit; no pending stage.* |

## Writing a plan

- Put new plans in `pending/`, never at the repo root.
- These files are tracked and public: no real tenant/`userId`, no absolute local
  paths, no real project or people names. Same rule as the test fixtures.
- Reference code with `File.swift:line` so the plan stays navigable.
- In the Done table, cite the **PR**, not a commit hash: the row ships in the same
  commit as the plan, and a commit can't contain its own hash.
- Never write a PR number before the PR exists. If the plan's branch is implemented
  but not yet opened, mark the row *unreleased* with the branch name and replace it
  with the real `[PR #N](…)` link once the PR is up.
- If a feature ever ships without a plan, one may be reconstructed afterwards — but
  say so at the top of the file and in the Done row. An archive that quietly implies
  it guided the code is worse than an admitted gap.
