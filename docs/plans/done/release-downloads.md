# Plan: Downloadable releases (DMG + zip)

*Planned and challenged in conversation, written and shipped in the same PR; no
pending stage.*

**Goal:** every release on GitHub carries an app people can download and install,
instead of having to build from source. Modelled on two sibling projects: one
publishes an arm64 zip from a tag-triggered workflow, the other a universal zip
built on the `xcode-27` preview runner.

## Decisions

- **Universal** (arm64 + x86_64). Nothing runs the x86_64 slice (CI only checks it's
  there with `lipo`, and the dev Mac has no Rosetta), so the README says "tested on
  Apple silicon only".
- **CI and release both on `xcode-27`**, Xcode pinned to 27.1 through
  `DEVELOPER_DIR`, matching local development. This drops the old `macos-14` / Swift
  5.10 CI and its "CI's compiler is older" caveat. Fallback: `macos-26` in both files
  at once (AGENTS.md).
- **Notes from an annotated tag** (`gh release create --notes-from-tag`), written with
  `git tag -a --cleanup=verbatim -F <file>`: the default cleanup (`strip`) deletes
  lines starting with `#`, i.e. Markdown headings. Releases v0.1.0–v0.4.0 were
  created by hand on GitHub and have no assets; they stay as they are.
- **DMG and zip**, each with a `.sha256`. The DMG holds the app and an `Applications`
  link for drag-to-install; no background image or icon layout (Finder scripting
  is flaky on CI), and no DMG signature (an ad-hoc one doesn't help Gatekeeper).
- **First downloadable release: 0.4.1**, bumped in this PR. Its notes must also cover
  what shipped since v0.4.0: Slack sync (#20, #21) and the Settings connection
  helpers (#23).

## Changes

1. `build_app.sh`: `UNIVERSAL=1` adds `--arch arm64 --arch x86_64`. The binary is
   copied from `swift build … --show-bin-path` instead of `$BUILD_PATH/release`: the
   folder depends on the toolchain (Xcode 27.1's default `swiftbuild` system uses
   `out/Products/Release` for both single- and multi-arch builds; older build systems
   put multi-arch builds elsewhere), so don't hard-code it. The flags are a string,
   not an array: macOS's bash 3.2 fails on an empty array under `set -u`.
2. `.github/workflows/ci.yml`: `xcode-27`, `DEVELOPER_DIR`, `UNIVERSAL=1`, an Xcode
   version check; the separate release build is gone (`build_app.sh` does one); a
   new step checks both architectures and `codesign --verify --strict`, since
   `build_app.sh` hides codesign failures.
3. `.github/workflows/release.yml` (new), on `v*` tags: full-history checkout (the
   commit count is `CFBundleVersion`), build, then fail unless the tag is
   `v<CFBundleShortVersionString>`, `BCBuild` is empty (the app shows `0.4.1`, not
   `0.4.1+<commit>`), both architectures are there and the signature verifies.
   Packages the zip (`ditto`) and DMG (`hdiutil`), re-fetches the annotated tag
   (checkout makes it lightweight) and publishes. It doesn't re-run the tests: CI
   must be green on the tagged commit.
4. `AppInfo.version` → 0.4.1.
5. README: a Download section (DMG first, zip as an alternative; Gatekeeper **Open
   Anyway** or `xattr`; after an update, Keychain prompts again and maybe **Reset
   permission**). The build requirement says Xcode, not the Command Line Tools.
6. AGENTS.md: the new CI, its fallback, and a Releasing section.

## Review findings folded in

A challenge pass before implementation found:

- The x86_64 slice is never run, and the planned Rosetta check couldn't run (Rosetta
  isn't installed) → README wording "tested on Apple silicon only", no Rosetta step.
- The plan named `.build/apple/Products/Release` as the universal output; on Xcode
  27.1 it's `out/Products/Release` → the comment explains why `--show-bin-path`
  stays instead of naming a folder.
- After an update the Keychain asks again (ad-hoc signing makes every build a new
  app to macOS, for *Chrome Safe Storage* and the Slack token) → in the README.
- The first-launch steps would only have been tested after publishing → the files
  were marked as downloaded (`com.apple.quarantine`) and checked locally before
  tagging (see Verify): the DMG itself isn't blocked, so no DMG step was needed.
- 0.4.1 breaks the minor-bump-for-features pattern (two features since v0.4.0);
  kept by choice.

## Verify

- `UNIVERSAL=1 ./build_app.sh` → `lipo -archs` shows `x86_64 arm64`, `codesign
  --verify --strict` passes; without `UNIVERSAL` the build is single-arch as before.
- The release steps (publish skipped) in a fresh clone with a local annotated
  `v0.4.1` tag pass: the app reports `0.4.1`, both `.sha256` files check. A wrong
  tag (`v0.4.2`) and a dirty tree (`BCBuild=<commit>.dirty`) fail. The DMG mounts
  with the app and an `Applications` link; the app verifies and is universal.
- Zip and DMG marked as downloaded (`com.apple.quarantine`), on macOS 27: the DMG
  still opens (Gatekeeper rejects it as unsigned when asked through `spctl`, but
  doesn't block mounting), so the README needs no DMG step. The app unzipped by
  Archive Utility and the app copied out of the DMG by Finder are both quarantined
  and rejected by Gatekeeper, as the README's **Open Anyway** / `xattr` step
  expects. The Open Anyway click itself wasn't exercised before release; after it,
  the published DMG downloaded in Chrome, installed to `/Applications` and launched
  after **Open Anyway** (quarantine flag marked approved, app shows `0.4.1`).
- macOS 27's `hdiutil` warns that `create` and `attach` are deprecated in favour of
  `diskutil image`; both still work.
- PR CI green on `xcode-27`; after merge, the `v0.4.1` tag publishes four assets.

## Not done

Notarization or a stable signing identity ([#22](https://github.com/asolfre/bizneo-companion/issues/22)),
an Intel runtime test, DMG artwork, re-running tests in the release job, building
the DMG in PR CI, a retry around `hdiutil` (re-run the job instead).
