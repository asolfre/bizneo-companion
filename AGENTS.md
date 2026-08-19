# AGENTS.md

Bizneo Companion — a macOS menu-bar app (Swift / AppKit) that reads your Bizneo HR
time balance and drives clock in/out by parsing Bizneo's **undocumented internal
HTML endpoints**, authenticated by reusing the Chrome session cookie.

## Build & verify

- **Local toolchain is Command Line Tools only (no full Xcode).** `swift test`
  fails locally (`could not determine XCTest paths` / `PlatformPath`). Use the
  built-in self-test instead — it's the canonical local check:
  ```
  swift run BizneoCompanion --selftest Tests/BizneoCompanionTests/Fixtures
  ```
  Covers parsers, calculator, chrono state, year aggregation, day-off logic, config
  defaults — offline, no Keychain/network.
- `swift test` (XCTest `ParserTests`) only runs on full Xcode (CI). CI is
  `.github/workflows/ci.yml` on `macos-14`: build (debug+release) → `swift test` →
  `--selftest` → `./build_app.sh`.
- Package the app: `./build_app.sh` → release build + assembles & ad-hoc-signs
  `BizneoCompanion.app` at repo root (`LSUIElement` agent, no Dock icon).
- Repo lives under Google Drive; pass `BUILD_PATH=/tmp/bc` to keep `.build` off the
  synced folder (e.g. `BUILD_PATH=/tmp/bc swift build`).
- macOS-only: links AppKit, Security, SQLite3, CommonCrypto. Won't build on Linux.

## Git & GitHub for this repo

- The remote is the SSH alias `git@github-asolfre:asolfre/bizneo-companion.git`
  (defined in `~/.ssh/config`, forcing the personal key via `IdentitiesOnly yes` +
  `IdentityFile ~/.ssh/github_asolfre`). **Don't switch it back to HTTPS:** this
  machine's git credential helper is macOS `osxkeychain` (inherited from the Command
  Line Tools system gitconfig, not from `~/.gitconfig`) and it resolves to a
  different GitHub account, so HTTPS pushes fail with
  `403 … denied to <other-user>`.
- `git` is covered by that alias, but **`gh` is not** — it always uses its globally
  active account. Before any `gh` write (`pr create`, `pr merge`, `workflow run`):
  ```
  gh auth switch --user asolfre       # ... make the change ...
  gh auth switch --user <other-user>  # switch back
  ```
  Read-only `gh` calls against this public repo work under either account.
- Commit identity comes from the **repo-local** `user.email`
  (`git config --local user.email` → the `asolfre` noreply address); the global
  `user.email` belongs to the other account. Don't rely on the global config.
- The `asolfre` token's scopes are `gist, read:org, repo` — **no `workflow`**. SSH
  pushes are unaffected, but editing `.github/workflows/*` through the `gh` API needs
  `gh auth refresh -h github.com -u asolfre -s workflow` first.

## Layout

- `Package.swift` at root (SwiftPM, **no external deps**).
- `Sources/BizneoCore/` — logic: `TimesheetParser` (HTML parsing), `Calculator`
  (today/week/month/year math), `Models`, `Config`, `BizneoClient`, `ChromeCookies`
  (cookie decrypt), `TimeFmt`.
- `Sources/BizneoCompanion/` — executable: `main`, `StatusItemController` (menu-bar
  UI), `Probe` (`--probe`/`--dump`), `SelfTest` (`--selftest`).
- `docs/plans/` — feature design docs, tracked. `pending/` = designed but not
  implemented, `done/` = shipped (kept as an archive, **never deleted**). When a plan
  ships, `git mv docs/plans/pending/<x>.md docs/plans/done/` in the same PR that
  implements it and update the tables in `docs/plans/README.md`.

## Gotchas when editing

- **Self-test/XCTest assertions hardcode exact fixture numbers** (e.g. month `-861`,
  reconcile `+134`, day-off correction `+360`). Changing `Calculator` or parsers
  means updating the magic numbers in `Sources/BizneoCompanion/SelfTest.swift`
  **and** `Tests/BizneoCompanionTests/ParserTests.swift`.
- **Adding a `Config` field requires a matching `decodeIfPresent` line in the custom
  `init(from:)`** (`Config.swift`) — the synthesized decoder is overridden, so a
  missing line silently drops the field and breaks old `config.json`.
- **Parsing: convert `NSRange`→`String.Index` with `Range(nsRange, in: html)`, never
  `index(_:offsetBy:)`.** Bizneo HTML has multibyte chars; offset math crashes
  ("String index out of bounds"). Guard regex capture-group ranges too.
- Parsers anchor on Bizneo CSS classes/labels (`schedule-issues`,
  `is-negative-balance`, `data-bulk-element`, `Until today`, and the configurable
  day-off schedule name). When Bizneo's markup changes, re-capture HARs and update
  `TimesheetParser`.
- **Plans are tracked docs, not scratch files.** New feature plans go straight to
  `docs/plans/pending/`, never the repo root.

## Data / privacy

- Fixtures `Tests/BizneoCompanionTests/Fixtures/*.html` are **anonymized** (real
  ids/names/projects scrubbed to placeholders like `Project A..H`). Originals are
  the raw HARs in `captures/` (gitignored). **Never re-introduce real PII** into
  tracked files.
- `Config` defaults are intentionally empty (`tenant`/`userId` = `""`); real values
  live only in `~/Library/Application Support/BizneoCompanion/config.json` (outside
  the repo). Don't hardcode a real tenant/userId.
- `--probe` hits the live Bizneo session (needs Chrome cookie + Keychain prompt +
  network); `--selftest` does not.
- Plans in `docs/plans/` are public like the fixtures: no real tenant/`userId`, no
  absolute local paths, no real project or people names.
