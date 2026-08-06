# Plan: Version single-source-of-truth + display

**Goal:** Establish a single source of truth for the app version (today it's
hardcoded twice in `build_app.sh` and never referenced by the app code) and
surface it to users.

**Decisions:**
- Source of truth: a **Swift constant** (Option A), `build_app.sh` derives the
  Info.plist version from it.
- Show the version in the **menu header**.
- Include a **self-test guard**.
- Bump version to **0.1.0**.

## Current state
- Version lives only in the generated `Info.plist` in `build_app.sh`
  (`CFBundleVersion` + `CFBundleShortVersionString`, both `1.0`).
- Swift code never reads a version. `main.swift` handles
  `--selftest` / `--probe` / `--once` / `--dump` but has no `--version`.
- Menu is built in `StatusItemController.rebuildMenu` (`StatusItemController.swift:162`);
  header is `header("Bizneo Companion")` at lines 167 and 193.

## 1. New file `Sources/BizneoCore/AppInfo.swift` (canonical source)
```swift
/// Single source of truth for the app version.
/// build_app.sh derives the Info.plist version from this constant.
public enum AppInfo {
    public static let name = "Bizneo Companion"
    public static let version = "0.1.0"
}
```

## 2. `Sources/BizneoCompanion/main.swift` — add `--version`
Insert before the `--probe` block (after the `--selftest` handling, ~line 16):
```swift
if args.contains("--version") || args.contains("-v") {
    print("\(AppInfo.name) \(AppInfo.version)")
    exit(0)
}
```
(`BizneoCore` is already imported.)

## 3. `Sources/BizneoCompanion/StatusItemController.swift` — version in menu header
Update **both** header call sites (lines **167** and **193**):
```swift
menu.addItem(header("Bizneo Companion v\(AppInfo.version)"))
```
(`BizneoCore` is already imported by this file.)

## 4. `build_app.sh` — derive plist version from the constant
- Add after the `APP_*` vars (~line 9):
  ```sh
  VERSION="$(grep -Eo 'version = "[^"]+"' Sources/BizneoCore/AppInfo.swift | grep -Eo '[0-9][^"]*')"
  ```
- Change the heredoc delimiter `<<'PLIST'` -> `<<PLIST` (unquoted; plist body has
  no `$`/backticks, so safe).
- Replace the two hardcoded lines (28-29):
  ```
  <key>CFBundleVersion</key>              <string>${VERSION}</string>
  <key>CFBundleShortVersionString</key>   <string>${VERSION}</string>
  ```

## 5. `Sources/BizneoCompanion/SelfTest.swift` — version guard
Add a small section (e.g. after `config defaults:`), asserting the version is
well-formed so a blank/malformed constant fails CI:
```swift
print("app info:")
check(!AppInfo.version.isEmpty, "version non-empty", AppInfo.version)
check(AppInfo.version.range(of: #"^\d+\.\d+"#, options: .regularExpression) != nil,
      "version looks like semver", AppInfo.version)
```
(No magic-number churn; purely additive.)

## Verify
- `swift run BizneoCompanion --version` -> `Bizneo Companion 0.1.0`
- `swift run BizneoCompanion --selftest Tests/BizneoCompanionTests/Fixtures`
  -> ALL PASSED (now includes the 2 version checks)
- `./build_app.sh` -> `plutil -p BizneoCompanion.app/Contents/Info.plist` shows
  `CFBundleShortVersionString = "0.1.0"` (and `CFBundleVersion`)
- Open the app -> menu header reads **"Bizneo Companion v0.1.0"**

## Notes / heads-up
- Two files reference the header string; both get the version. The loading/error
  pre-data state (line 200) still says plain "Bizneo Companion" — left as-is
  (open question: version it too?).
- This is additive; no existing magic numbers change, so `ParserTests`/`SelfTest`
  fixture assertions are unaffected.
