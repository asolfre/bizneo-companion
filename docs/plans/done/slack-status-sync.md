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
- **Mode:** `Config.slackMode` (segmented picker, default `statusAndPresence`):

  | Mode | Writes | Token scopes |
  |---|---|---|
  | `statusAndPresence` | status + presence | `users.profile:read`, `users.profile:write`, `users:write` |
  | `statusOnly` | status; presence never touched (no sticky `away`) | `users.profile:read`, `users.profile:write` |
  | `presenceOnly` | presence only; still follows Bizneo even under a manual status | `users:write` |

  In `statusAndPresence` a manual status blocks presence too (you're on vacation,
  don't flip the dot). Narrowing the mode undoes what the old one wrote and the new
  one won't — `SlackSyncMode.cleanup(from:to:)`: e.g. → `presenceOnly` clears our
  status, → `statusOnly` sets presence back to `auto`. Widening needs no cleanup.
- **Token:** a user token (`xoxp-…`) with `users.profile:read`, `users.profile:write`,
  `users:write`. Stored in the login Keychain (`SlackToken`, service
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

## Verification

- `--selftest`: all seven state mappings, presence values, the ownership guard, the
  three modes' `setsStatus`/`setsPresence`, the mode-change cleanup table, and the
  `slackSync`/`slackMode` config round-trip / legacy defaults.
- Manual, in a real workspace (to record here): check in → 💻; break → ☕ + away;
  check out → cleared + away; set a manual status → left alone; quit → status
  expires; toggle off → cleared + `auto`; `presenceOnly` with a manual status →
  status kept, presence follows; `statusOnly` → presence never changes; switch
  `statusAndPresence` → `presenceOnly` → our status cleared.
