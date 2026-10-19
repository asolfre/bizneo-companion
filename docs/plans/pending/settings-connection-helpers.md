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
- [ ] Manual checks recorded below; plan moved to `done/`

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
  `Cookies` file, sorted by name. Any read or parse failure → `[]`, never a throw:
  Chrome's layout is undocumented and has changed before.
- `ChromeCookies.hasSessionCookie(profile:host:) -> Bool`: one-line wrapper around
  `readEncryptedCookies` for `_hcmex_key` only.
- Settings, same pattern as the default-project picker:
  - list non-empty → `Picker`; a configured directory that wasn't detected keeps
    its own row, so a working value is never hidden or overwritten;
  - list empty → the existing `TextField`.
- Markers come from `.task(id: cfg.tenant)` after a 0.5 s pause: editing the
  tenant cancels and restarts it, so first-run setup works (type the tenant, then
  pick the profile). The window never waits for it.

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
  …"), a dead session is "Not logged in", a wrong user ID is the parse failure.
- A manual cookie bypasses Chrome entirely (`BizneoClient.cookieHeader`), so a pass
  then says nothing about the profile: the result adds "manual cookie; Chrome
  profile not used".
- Disabled while running (with a spinner) and until tenant and user ID are set.
  Editing tenant, user ID, profile or manual cookie clears the result, so a ✓ never
  sits next to values it didn't test.
- May trigger the one-time "Chrome Safe Storage" Keychain prompt — said next to the
  button and in the README's Settings paragraph. Hits the live session, so it stays
  out of `--selftest`.

## Verification

- `--selftest` (offline): `profiles(chromeDir:)` against a temporary directory — two
  profiles, one without a `Cookies` file (excluded); a `System Profile` directory
  not in `info_cache` (excluded); malformed `Local State` → `[]`.
  `connectionCheck` passes on the `hub_chrono.html` + `my_logs.html` fixtures and
  fails when either is empty.
- Manual (to record here): picker names match Chrome's profile menu; only the
  profiles with a Bizneo session are marked; correct values → ✓; wrong tenant →
  "no cookies" error; wrong user ID → error; manual cookie → the result mentions
  it; the window still opens instantly.
