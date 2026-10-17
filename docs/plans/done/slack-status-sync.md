# Slack status sync

Issue [#13](https://github.com/asolfre/bizneo-companion/issues/13): mirror the clock
state (working / on a break / out) into Slack's status and presence.

*Planned and challenged in conversation, then written alongside the code; no pending
stage.*

## Behaviour

| `BarState` | Slack status | Presence |
|---|---|---|
| `working` | 💻 Working | `auto` |
| `onBreak` | ☕ On a break | `away` |
| `notCheckedIn`, `checkedOutEarly`, `doneForToday`, `offDuty` | cleared | `away` |
| `unknown`, failed refresh | nothing sent | nothing sent |

- **Toggle:** `Config.slackSync` (default off), in Settings → Slack. Disabled until a
  token is entered. Turning it off (or clearing/replacing the token) clears our
  status and sets presence back to `auto` with the old token. User-facing setup
  (creating the Slack app and token) lives in the README → *Slack sync*.
- **Mode:** `Config.slackMode` (segmented picker, default `presenceOnly` — the least
  intrusive option, and the only one needing just a single scope, `users:write`):

  | Mode | Writes | Token scopes |
  |---|---|---|
  | `presenceOnly` | presence only; still follows Bizneo even under a manual status | `users:write` |
  | `statusOnly` | status; presence never touched (no sticky `away`) | `users.profile:read`, `users.profile:write` |
  | `statusAndPresence` | status + presence | `users.profile:read`, `users.profile:write`, `users:write` |

  In `statusAndPresence` a manual status blocks presence too (you're on vacation,
  don't flip the dot). Narrowing the mode undoes what the old one wrote and the new
  one won't — `SlackSyncMode.cleanup(from:to:)`: e.g. → `presenceOnly` clears our
  status, → `statusOnly` sets presence back to `auto`. Widening needs no cleanup.
- **Token:** a user token (`xoxp-…`) with the scopes for the chosen mode (table
  above). Stored in the login Keychain (`SlackToken`, service
  `BizneoCompanion.Slack`), never in `config.json`. The ad-hoc-signed app may
  re-prompt for Keychain access after a rebuild.
- **Rolling expiry:** working/break statuses expire after 2 × `refreshSeconds` and are
  re-sent on every refresh, so a quit, crash or sleep lets Slack drop them by itself.
  A clear, or presence alone, is sent once per state change.
- **Manual statuses win:** before writing, `users.profile.get` reads the current
  status. Unless it is empty or exactly one of ours (text + emoji), nothing is
  changed — presence included.
- **Errors:** Slack replies HTTP 200 with `"ok": false`, so `ok` is checked. A failure
  is logged (`NSLog`) and retried on the next refresh.

## Code

- `Sources/BizneoCore/SlackStatus.swift` — pure `target(for:)` / `isOwned`, the
  three API calls, and the `SlackToken` Keychain helper.
- `StatusItemController.syncSlack` — called only from `apply(_:)`: `applyError` must
  not touch Slack, and `doClock` already ends in a refresh. Cleanup on disable lives
  in `applyConfig`.
- `SettingsWindowController.slackSection` — toggle, secure token field, Clear.

## Review findings folded in

1. The first sketch mapped three states ("working, break, out"); `BarState` has seven,
   and `unknown` must not clear a status mid-day.
2. `users.setPresence` accepts only `auto`/`away` — there is no `active`. `away` is
   sticky until `auto` is sent, hence the cleanup on disable.
3. The app had no Keychain *write* code (only reads Chrome's password); `SlackToken`
   adds it.
4. Without expiry and an ownership check, the sync would clobber manual statuses and
   leave "Working" behind after a quit.
5. Dedup must record only confirmed pushes, or a failed one is never retried.

## Follow-ups (after the first PR)

Shipped in a second PR, once presence-only became the default:

1. **Quit resets presence.** Statuses expire on their own, presence doesn't, so a
   quit on a break or after checkout left a sticky `away`. `AppDelegate`'s
   `applicationShouldTerminate` (quit, logout, shutdown) now sends `auto` when the
   last confirmed push was `away`, waiting at most 3 s. A crash or force-quit still
   leaves `away` until the next launch pushes — recorded as a `ponytail:` ceiling.
2. **README:** the "No password, no API token" line now notes that Slack sync is the
   one optional exception.
3. **Fewer Keychain writes:** Settings only writes the token when it changed. With
   the ad-hoc-signed app, every Keychain access can re-prompt after a rebuild.

## Verification

- `--selftest`: all seven state mappings, presence values, the ownership guard, the
  three modes' `setsStatus`/`setsPresence`, the mode-change cleanup table, and the
  `slackSync`/`slackMode` config round-trip / legacy defaults.
- Manual, in a real workspace (build `0.4.0+e023c8a`):

  | Check | Result |
  |---|---|
  | Presence follows the clock state | ✅ passed |
  | Check in → 💻 Working | not yet tested |
  | Break → ☕ + away | not yet tested |
  | Check out → cleared + away | not yet tested |
  | Manual status → left alone | not yet tested |
  | `presenceOnly` with a manual status → status kept, presence follows | not yet tested |
  | `statusOnly` → presence never changes | not yet tested |
  | `statusAndPresence` → `presenceOnly` → our status cleared | not yet tested |
  | Quit while working → status expires | not yet tested |
  | Toggle off → cleared + `auto` | not yet tested |
  | Quit while away → presence back to `auto` | not yet tested |
