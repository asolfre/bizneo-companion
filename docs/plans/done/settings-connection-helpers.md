# Plan: Settings connection helpers

Goal: finish the two parts of [`done/add-settings-screen.md`](../done/add-settings-screen.md)
that were deliberately cut when the Settings window shipped — **Chrome profile
auto-detect** and **Test connection**. Both concern the Account section, both touch
the live cookie path, and both are pure convenience over fields that already work.

## Steps

- [x] Profile enumeration and session check in `ChromeCookies`
- [x] `BizneoClient.testConnection()` with a pure `connectionCheck`
- [x] Account section: profile picker, session markers, Test connection
- [x] Self-test, README Settings paragraph
- [x] macOS privacy block: detection, menu action, Settings hint with Reset permission (§3)
- [x] Manual checks recorded below; plan moved to `done/`

## Context

The Settings window (`Sources/BizneoCompanion/SettingsWindowController.swift`) is
SwiftUI in an `NSHostingController`. Its Account section holds `tenant`, `userId`
and `chromeProfile`; `chromeProfile` is a plain `TextField` today, and nothing
checks the three values before they're saved. Neither gap is a regression.

## Corrections to the first draft

Checking the first draft against the code and a real Chrome install changed four
things:

1. **Names come from `Local State`, not each profile's `Preferences`.** A profile's
   `Preferences` → `profile.name` can differ from what Chrome's profile menu shows
   (seen in practice: a stale "Person 1"). Chrome's own list is
   `Chrome/Local State` → `profile.info_cache`, keyed by directory: one file
   instead of one per profile, and it lists only real profiles — `System Profile`
   and `Guest Profile` have `Preferences` and `Cookies` files but aren't pickable.
2. **The Bizneo-session marker doesn't need the Keychain.** The first draft treated
   it as Keychain work. Chrome stores each cookie's `host_key` in plain text; only
   the value is encrypted. `ChromeCookies.readEncryptedCookies(profile:host:names:)`
   already does exactly this read (copy the DB, query by host) without the
   Keychain, with the same predicate a refresh uses. It still copies a file per
   profile, so it runs off the main thread.
3. **A cookie isn't a login.** More than one profile can hold a Bizneo session cookie
   (seen in practice: two), and an old one may be expired. The marker says "has a
   Bizneo session"; Test connection is what proves it works.
4. **Test connection doesn't run `refresh()`.** With the year total on, a fresh
   client fetches every past month (up to 12 requests), and Bizneo has answered
   HTTP 200 for broken sessions before (`BizneoClient.swift`, `isLoginResponse`), so
   a response proves nothing on its own. See §2.

## Decisions

| Question | Decision |
|---|---|
| Which profiles get the session marker? | Those with a `_hcmex_key` cookie for `<tenant>.bizneohr.com` — the existing lookup, no new query. Markers appear once a tenant is typed. *Rejected:* matching any `*.bizneohr.com` and suggesting the tenant (needs a new query). |
| Picker label | `Name — email (folder)`, e.g. `Work — you@company.com (Profile 3)`; email omitted when the profile isn't signed in. Shown only in the window, never saved. |
| What counts as a successful test? | Both requests a refresh starts with must parse: the clock state isn't `unknown` **and** this month's balance is found. Catches a wrong user ID whatever Bizneo does with it. |
| Where's the button? | Bottom of the Account section. |
| Order with PR #21 | Branch from `main` in parallel; whichever merges second rebases. |

## 1. Chrome profile picker

- `ChromeCookies.profiles(chromeDir:) -> [ChromeProfile]` (`dir`, `name`, `email`):
  reads `Local State` → `profile.info_cache`, keeps entries whose directory has a
  `Cookies` file, sorted like Finder (`localizedStandardCompare`), then by
  directory so equal names stay stable. A missing or unparsable file → `[]`:
  Chrome's layout is undocumented and has changed before. It throws only when the
  file exists but can't be read (§3).
- `ChromeCookies.hasSessionCookie(profile:host:)`: wraps `readEncryptedCookies`
  for `_hcmex_key` only; "no" on any failure except the privacy block (§3).
- Settings, same pattern as the default-project picker:
  - list non-empty → `Picker`; a configured directory that wasn't detected keeps
    its own row, so a working value is never hidden or overwritten;
  - list empty → the existing `TextField`.
- The list and the markers load in `.task(id: cfg.tenant)`, detached from the main
  thread: `Local State` sits behind the macOS privacy check (§3), and the window
  must never wait on its prompt. Until the list arrives the text field shows.
  Markers follow a 0.5 s pause: editing the tenant cancels and restarts it, so
  first-run setup works (type the tenant, then pick the profile).

## 2. Test connection

- `BizneoClient.testConnection() -> ChronoStatus` sends exactly `fetchHubChrono()`
  and `fetchMonthLogs(current Madrid month)` — no year total, no pending
  change-request lookups.
- The verdict is a pure `BizneoClient.connectionCheck(hub:logs:)`: throws
  `BizneoError.parse` unless `parseChronoState(hub).status != .unknown` and
  `parseMonthBalance(logs) != nil`. Covered by the self-test on the fixtures.
- Built from the form's **unsaved** values (a `BizneoClient` over the working copy
  of `Config`), not the live config.
- Result inline: `✓ Connected · clock running` / `on a break` / `stopped`, or the
  exact `BizneoError` text. The useful failures tell themselves apart: a wrong
  tenant fails before any request ("No cookies for x.bizneohr.com in Chrome profile
  …"), a dead session is "Not logged in". A wrong user ID was expected to be the
  parse failure, but Bizneo answers **HTTP 404** for an unknown user ID (seen in
  testing), so Test connection turns a 404 into "Bizneo returned HTTP 404: check
  the User ID". Only there: in the menu bar a 404 could also mean Bizneo changed
  its pages. The parse check stays as the guard against a 200 with the wrong page.
- A manual cookie bypasses Chrome entirely (`BizneoClient.cookieHeader`), so a pass
  then says nothing about the profile: the result adds "· manual cookie, Chrome
  profile not used".
- Disabled while running (with a spinner) and until tenant and user ID are set.
  Editing tenant, user ID, profile or manual cookie clears the result, so a ✓ never
  sits next to values it didn't test.
- May trigger the one-time "Chrome Safe Storage" Keychain prompt — said next to the
  button and in the README's Settings paragraph. Hits the live session, so it stays
  out of `--selftest`.

## 3. macOS privacy block on Chrome's data

Found during manual testing, after the test Mac was upgraded from macOS 14.8.9 to
27.0.1 (the version that introduced it is unknown; "seen on 27"):

- Reading Chrome's data (`Local State`, `Profile N/Cookies`) now needs a per-app
  permission, listed under Privacy & Security → **Files & Folders** →
  BizneoCompanion → Google Chrome. Without it, `stat` still works but opening the
  files fails with "Operation not permitted" — so the old code reported
  "Chrome cookie DB not found" for a file that was there.
- The permission belongs to **one build**. The app is ad-hoc signed, so every build
  is a different app to macOS. With the grant held by the `/Applications` build, a
  test build stayed blocked, and switching its toggle on didn't stick — from the
  Google Drive repo folder and from `~/Applications` alike, with only one copy
  running. Only `tccutil reset All com.asolfre.bizneocompanion`, reopening the app
  and clicking **Allow** on the prompt fixed it. An in-place update in
  `/Applications` is expected to behave the same; not yet observed.

What ships:

- `BizneoError.chromeAccessBlocked` ("macOS is blocking access to Chrome's data"):
  thrown when a Chrome file **exists but can't be read**, whatever the error code.
  That way the self-test's unreadable (`000`) file takes the same path as the real
  block (`EACCES` vs `EPERM`). Kept short: it's a menu line and the body of the
  "Can't check your Bizneo status" notification. It names no app, because `--probe`
  run from Terminal reads Chrome as Terminal.
- Menu: that error line gets **Open Privacy & Security…** (Files & Folders), checked
  before the `"cookie"` match that adds **Open Bizneo to log in** — logging in again
  doesn't lift a macOS block.
- Settings → Account: when any read of Chrome's data is blocked (the profile list,
  a marker, or Test connection), a hint lists the steps: allow Google Chrome; if the
  toggle switches itself off, **Reset permission** (runs `/usr/bin/tccutil reset All
  <bundle id>`), then quit, reopen and Allow; close Settings and open it again. If
  the reset fails, the hint shows the command with **Copy**.
- README (Quick start, Settings, FAQ) and `AGENTS.md` (testing builds) explain it.
- *Not here:* a stable signing identity, which should let the permission survive
  updates — [#22](https://github.com/asolfre/bizneo-companion/issues/22).

## Review findings folded in (second round)

A review of the macOS-block plan, before code, changed it:

1. The hint first said only "allow it, then reopen Settings" — the exact step that
   failed in testing once the permission belonged to another build. Added Reset
   permission.
2. The new error would have contained "cookie", so the menu would have offered
   **Open Bizneo to log in** for a permission problem; and a long message (with the
   `tccutil` command) would have been a very wide menu line and a cut-off
   notification. Short message, dedicated menu action.
3. "Blocked" is "exists but unreadable", not a specific errno, so the self-test's
   `000` file covers the same branch as the real `EPERM`.
4. Choosing Settings… while the window is open only brings it forward
   (`SettingsWindowController.show`), so the hint says *close* and reopen.
5. `Local State` was read on the main thread while the window was built; it's
   behind the privacy check now, so it loads detached.
6. Self-test sort names are ASCII only (`localizedStandardCompare` is locale-aware).

## Decisions (second round)

| Question | Decision |
|---|---|
| Recovery when the toggle won't stick | **Reset permission** button running `tccutil`; the command with Copy if that fails. *Rejected:* command only; README only. |
| Picking up a new grant | The hint says close Settings and open it again. *Rejected:* a Check again button; automatic retries. |
| Profile list loading | Detached, after the window is up (text field until it arrives). |
| Menu when blocked | Short line + **Open Privacy & Security…**. *Rejected:* an action opening Settings. |
| Signing | Separate issue, fixed later: [#22](https://github.com/asolfre/bizneo-companion/issues/22). |

## Verification

- `--selftest` (offline), against a temporary directory: `profiles(chromeDir:)` lists
  only `info_cache` profiles with a `Cookies` file (a `System Profile` directory and
  a profile without a jar are excluded), in Finder order with a lowercase name and a
  tie on name; malformed or missing `Local State` → `[]`; an unreadable (`000`)
  `Local State` or cookie jar → `chromeAccessBlocked`, not "not found";
  `hasSessionCookie` is "no" for a jar without the cookie and a missing profile.
  `connectionCheck` passes on the `hub_chrono.html` + `my_logs.html` fixtures and
  fails when either is empty.
- Manual, build `0.4.0+fe0aef5` (before §3):

  | Check | Result |
  |---|---|
  | Picker names match Chrome's profile menu; configured profile selected | ✅ |
  | Only the profiles with a Bizneo session are marked | ✅ after reopening Settings; ❌ on the first open, while access was still blocked (no hint then — fixed by §3) |
  | Correct values → ✓ | ✅ "Connected · clock stopped" |
  | Sort order | ❌ byte order put "OLD …" before lowercase names — fixed (Finder order) |
  | Blocked access (macOS 27) | ❌ "Chrome cookie DB not found", text field, no markers — fixed by §3 |

- Manual, build `0.4.0+0b02803` (after §3, before the 404 hint):

  | Check | Result |
  |---|---|
  | Picker names match Chrome's menu, Finder order | ✅ |
  | Session markers | ✅ |
  | Wrong tenant | ✅ "Couldn't read Chrome cookie: No cookies for …", before any request |
  | Wrong user ID | ⚠️ "Bizneo returned HTTP 404" — fails correctly, but didn't name the field; the "check the User ID" hint was added after |
  | Manual cookie | ✅ the result says the Chrome profile isn't used |
  | Window opens instantly | ✅ |
  | Blocked (grant held by another build): menu line + **Open Privacy & Security…**, no log-in action | ✅ |
  | **Open Privacy & Security…** opens Files & Folders | ✅ |
  | Settings hint; **Reset permission** from inside the app | ✅ the button worked (no Copy fallback needed) |
  | After Allow + reopening Settings: picker and markers back | ✅ |
