# Plan: Settings connection helpers

Goal: finish the two parts of [`done/add-settings-screen.md`](../done/add-settings-screen.md)
that were deliberately cut when the Settings window shipped — **Chrome profile
auto-detect** and **Test connection**. Both concern the Account section, both touch
the live cookie/Keychain path, and both are pure convenience over fields that already
work. That's why they were split out rather than delaying the window.

## Context

The Settings window exists (`Sources/BizneoCompanion/SettingsWindowController.swift`),
is SwiftUI in an `NSHostingController`, and already has an Account section holding
`tenant`, `userId` and `chromeProfile`. `chromeProfile` is a plain `TextField` today.

`ChromeCookies` (`Sources/BizneoCore/ChromeCookies.swift`) already knows how to locate
a profile directory and decrypt its cookie jar — the enumeration below should reuse
whatever path-building it does rather than re-deriving Chrome's layout.

Neither item is a regression today: both fields are editable, just without help.

## 1. Chrome profile auto-detect

Replace the `chromeProfile` `TextField` with a `Picker` over detected profiles,
keeping a custom/editable fallback.

- Enumerate `~/Library/Application Support/Google/Chrome/*/` for directories that
  contain a `Cookies` file.
- Friendly name from each profile's `Preferences` JSON (`profile.name`), falling back
  to the directory name. Show both, e.g. `Work (Profile 1)`.
- Flag profiles that hold a `*.bizneohr.com` cookie — that's the one the user wants,
  and it's the actual question they're trying to answer.
- **Keep a custom-value fallback.** Same failure mode as the default-project picker:
  if detection finds nothing (unusual Chrome install, sandboxing, a renamed
  directory), a bare `Picker` renders blank and can hide (or, untested, overwrite) a working
  `chromeProfile` on the next save. Fall back to the `TextField` when the list is
  empty, and make sure an already-configured profile that wasn't detected is still
  selectable.
- Reading `Preferences` is plain JSON on disk, no Keychain, so this is safe to do
  synchronously while the window builds. Flagging the Bizneo cookie is **not** — it
  reads the cookie jar. Either do it off the main thread and fill the flags in when
  they arrive, or fold it into Test connection below and skip the flag.

## 2. Test connection

A button in the Account section that validates the **current, unsaved form values**
before the user commits to them.

- Build a temporary `BizneoClient` from the form's `Config` working copy — not from
  `self.config`, or it tests the old settings.
- Run one `refresh()`.
- Show the result inline: `✓ Connected · working since 09:48`, or the exact error
  text from `BizneoError` (not a generic failure — the useful cases are "not logged
  in", "wrong tenant" and "no cookie for that profile", and they need telling apart).
- Disable the button while in flight and show progress; a Bizneo round-trip is not
  instant.
- May trigger the one-time Keychain "Chrome Safe Storage" prompt. That's expected —
  say so next to the button, and note it in the README's Settings paragraph.
- It hits the live session, so it belongs nowhere near `--selftest`.

## Tests / build

- No `BizneoCore` logic changes expected; if profile enumeration lands in `BizneoCore`
  it needs a self-test that runs against a temporary fixture directory, not the real
  `~/Library`.
- The existing all-fields `Config` round-trip check in `SelfTest.swift` still covers
  the save path.
- Rebuild `BizneoCompanion.app`.

## Notes / risks

- **Don't block window presentation on disk or network work.** The window must open
  instantly; detection results can populate afterwards.
- Chrome's profile directory layout is undocumented and has changed before — treat a
  parse failure as "no profiles detected" and fall through to the text field rather
  than throwing.
