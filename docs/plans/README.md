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

Suggested order — smallest/least invasive first, and #4 after #3 so the settings UI
can expose `carryoverScope` in a single pass.

| # | Plan | Summary |
|---|---|---|
| 1 | [`pending/versioning.md`](pending/versioning.md) | Single source of truth for the app version (`AppInfo.swift`), derived by `build_app.sh`, shown in the menu header. Unblocks tagged releases. |
| 2 | [`pending/past-month-change-requests.md`](pending/past-month-change-requests.md) | Bug: the "Pending changes" section disappears after a month rollover even though the year figure still counts those requests. Retain per-month pending in the `BizneoClient` year cache. |
| 3 | [`pending/configurable-carryover-scope.md`](pending/configurable-carryover-scope.md) | New `carryoverScope` config (`none`/`week`/`month`/`year`) folding a backlog into the menu-bar **Today** figure. |
| 4 | [`pending/add-settings-screen.md`](pending/add-settings-screen.md) | Native Settings window replacing "Edit configuration…" (raw JSON), with launch-at-login and connection test. Largest of the four. |

## Done

| Plan | Shipped in |
|---|---|
| [`done/live-ticker.md`](done/live-ticker.md) | `d6ebbad`, `7fcbfc1` (PR #2) — reconcile today's running timer into week/month/year + smooth live tick |
| [`done/configurable-seconds.md`](done/configurable-seconds.md) | `b317131` (PR #2) — `Config.dropdownSecondsScope` (`none`/`today`/`all`), default `today` |

## Writing a plan

- Put new plans in `pending/`, never at the repo root.
- These files are tracked and public: no real tenant/`userId`, no absolute local
  paths, no real project or people names. Same rule as the test fixtures.
- Reference code with `File.swift:line` so the plan stays navigable.
