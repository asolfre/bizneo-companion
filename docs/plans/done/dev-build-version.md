# Plan: Tell development builds apart from releases

Follows [`versioning.md`](versioning.md), which made `AppInfo.version` the single source
of truth. That still holds: this only adds *which build* to *which version*.

## Problem

Every build showed `AppInfo.version` alone. A build from a feature branch looked
exactly like the release it followed, so during manual testing two different builds
both reported `0.2.0`, and later `0.3.0`. The only way to tell which one was running
was comparing CDHashes from `codesign -dvvv`.

## Decisions

- **Automatic, from git.** No manual `-rc.N` suffix: you have to remember to set it,
  and forgetting it brings the original problem back. Apple also expects the bundle's
  version fields to be plain numbers.
- **Format:** `0.3.0` for a release; `0.3.0+d8c9728` for anything else, with `.dirty`
  added when there are uncommitted changes; `0.3.0+dev` when not running from an app
  bundle (`swift run`). The `+` is semver's build-metadata separator: "this is 0.3.0
  plus commit d8c9728", not a pre-release of it.
- Shipped as a separate commit on the check-in reminders branch, not as its own PR.

## Design

- **`build_app.sh`** works out the build identity before writing the Info.plist:
  - **`BCBuild`** (new key): empty when `HEAD` is exactly at tag `v$VERSION` and there
    are no uncommitted changes to tracked files; otherwise `git rev-parse --short HEAD`
    plus `.dirty`. Without git (e.g. a source tarball) it's empty, so the bare version
    shows rather than the build failing.
  - **`CFBundleVersion`**: the commit count (`git rev-list --count HEAD`). It was the
    version string before. It stays numeric as Apple expects, and Finder's Get Info
    shows "0.3.0 (33)".
  - **`CFBundleShortVersionString`**: unchanged, `AppInfo.version`.
  - The script's last lines print what it stamped.
- **`AppInfo`**: `build` reads `BCBuild` from the bundle; `displayVersion` combines it
  through `display(version:build:)`, a pure function the self-test covers.
- **Display**: `--version` (`main.swift`), the menu header (`StatusItemController.swift`,
  two places) and the Settings footer use `displayVersion`. Logic that needs the
  release version (the `build_app.sh` scrape, the self-test's semver check) keeps
  `AppInfo.version`.

## Verification

- Self-test: release (`""` → `0.3.0`), branch commit, `.dirty`, unbundled (`nil` →
  `+dev`). Making the release case show its commit fails the first check.
- `build_app.sh` on this branch with uncommitted changes: prints and stamps
  `0.3.0+d8c9728.dirty (build 33)`; the bundled `--version` reads it back.
- The release case of the stamping logic, run in a temporary worktree at `v0.3.0`:
  `BUILD=''`, display `0.3.0`. Still worth one look at the next real release build.

## Known gaps

- Two builds of the same commit with *different* uncommitted edits both show `.dirty`.
  Adding the build time would separate them; not needed so far.
- Untracked files don't count as dirty (`git diff --quiet HEAD` ignores them).
- A release PR's own build (version bumped, tag not created yet) shows
  `0.4.0+<commit>`. Correct: it isn't the release until it's tagged.
