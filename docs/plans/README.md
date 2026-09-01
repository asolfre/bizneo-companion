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

## Pending

Suggested order — smallest/least invasive first, and #2 after #1 so the settings UI
can expose `carryoverScope` in a single pass.

| # | Plan | Summary |
|---|---|---|
| 1 | [`pending/configurable-carryover-scope.md`](pending/configurable-carryover-scope.md) | New `carryoverScope` config (`none`/`week`/`month`/`year`) folding a backlog into the menu-bar **Today** figure. |
| 2 | [`pending/add-settings-screen.md`](pending/add-settings-screen.md) | Native Settings window replacing "Edit configuration…" (raw JSON), with launch-at-login and connection test. Largest of the two. |

## Done

| Plan | Shipped in |
|---|---|
| [`done/live-ticker.md`](done/live-ticker.md) | [PR #2](https://github.com/asolfre/bizneo-companion/pull/2) — reconcile today's running timer into week/month/year + smooth live tick |
| [`done/configurable-seconds.md`](done/configurable-seconds.md) | [PR #2](https://github.com/asolfre/bizneo-companion/pull/2) — `Config.dropdownSecondsScope` (`none`/`today`/`all`), default `today` |
| [`done/expected-checkout-time.md`](done/expected-checkout-time.md) | [PR #3](https://github.com/asolfre/bizneo-companion/pull/3) — `🏁 Leave by HH:MM` in the working clock section; `Calculator.expectedCheckout` + `TimeFmt.clock`. *Plan reconstructed after the fact.* |
| [`done/checkout-alert-icon.md`](done/checkout-alert-icon.md) | [PR #4](https://github.com/asolfre/bizneo-companion/pull/4) — tinted SF Symbols on both `NSAlert`s via a shared `alertIcon` helper; no bundled assets |
| [`done/menu-bar-clock-states.md`](done/menu-bar-clock-states.md) | [PR #6](https://github.com/asolfre/bizneo-companion/pull/6) — `BarState` splits Bizneo's single `.stopped` into not-checked-in / checked-out-early / done / off-duty; SF Symbol status icons, orange "Check in" warning |
| [`done/versioning.md`](done/versioning.md) | [PR #8](https://github.com/asolfre/bizneo-companion/pull/8) — `AppInfo` as the single source of truth, scraped by `build_app.sh` for the Info.plist; `--version` flag and version in the menu header. First tagged release, v0.1.0. |
| [`done/past-month-change-requests.md`](done/past-month-change-requests.md) | *unreleased* — `feature/past-month-pending` — `MonthTotal` retains each past month's requests so the "Pending changes" list stops emptying out after a month rollover; dedup/sort extracted to `Calculator.mergePending` to make it testable |

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
