# ⏱️ Bizneo Companion

[![Platform: macOS 13+](https://img.shields.io/badge/platform-macOS%2013%2B-black?logo=apple)](https://www.apple.com/macos/)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)](https://swift.org)
[![License: CC BY-NC 4.0](https://img.shields.io/badge/License-CC%20BY--NC%204.0-lightgrey)](LICENSE)

**Your Bizneo time balance, live in the macOS menu bar — with one‑click clock in/out.**

Stop opening Bizneo a dozen times a day to check whether you're ahead or behind.
Bizneo Companion puts your running time balance right in the menu bar and lets you
**check in, take a break, resume, and check out** without leaving what you're doing.

> Unofficial, community‑built helper for [Bizneo HR](https://www.bizneo.com/)
> time tracking (*control horario / fichaje / registro de jornada*). Not affiliated
> with Bizneo.

<!-- TODO: replace with a real screenshot or GIF (see docs/) -->
<!-- ![Bizneo Companion in the menu bar](docs/screenshot.png) -->

```text
         ▶︎  −0:29          ← menu bar (red = behind · green = ahead)
         ╰───────────────────────────────╮
           Bizneo Companion              │
           ─────────────────────────────  │
           🔴 Today        missing 0:29   │
           🟢 This week    ahead   2:11   │
           🔴 This month   missing 1:01   │  (official −8:21, +7:20 pending)
           🟢 This year    ahead  14:30   │
           ─────────────────────────────  │
           🟢 Working (telework) · 09:48  │
           🏁 Leave by 18:15              │
              Take break                  │
              Check out…                  │
           ─────────────────────────────  │
           Pending changes (2)         ▸  │
           ─────────────────────────────  │
           Refresh now · Settings… · Quit
         ╰───────────────────────────────╯
```

…and when you forget to clock in, the bar stops showing a number at all:

```text
         ⏰  Check in       ← orange: hours expected today, timer not running
```

## Why you'll like it

- 👀 **Always visible** — your balance sits in the menu bar; glance instead of logging in.
- ➕ **Counts what's pending** — unapproved time‑edit requests are folded in, so the
  number matches reality, not just what's been approved.
- 🟢 **Net ahead/behind at a glance** — the bar shows your **cumulative week** by
  default (green when you've banked extra, red when you owe time).
- 🕒 **Clock in/out from the menu** — check in (with project), break, resume, check out.
- 🏖️ **Knows your days off** — company free Fridays ("Fridom") don't get counted as
  missing time.
- 🔐 **No password, no API token** — reuses your existing Chrome session, all locally.
  (The optional [Slack sync](#slack-sync) is the one feature that needs a token.)

## Features

| | |
|---|---|
| 📊 **Today / week / month / year** | Running balance for each period, pending‑aware |
| ⏰ **Forgot‑to‑clock‑in warning** | The bar turns orange and says **Check in** when hours are expected today and the timer isn't running |
| ⏯️ **Clock controls** | Check in · Take break · Resume · Check out (with confirm) |
| 🏁 **Leave‑by time** | While clocked in, the wall‑clock time you hit today's target |
| 🗂️ **Project picker** | Check in to a project; remembers your last one |
| 🏠 **Telework by default** | Configurable office/telework mode |
| 🏖️ **Day‑off aware** | Free "Fridom" Fridays don't count against you |
| 🔄 **Auto‑refresh** | Every 10 min (configurable) + on demand |
| ⚙️ **Settings window** | Every option in a real form — no JSON editing, applies without a restart |
| 🔔 **Check‑in reminders** | A notification with a **Check in** (or **Resume**) button when you haven't started, checked out early, or are still on a break, inside time windows you choose. **Not today** silences it until tomorrow. |
| 💬 **Slack sync** *(optional)* | Mirrors working / on a break / off into your Slack status and/or presence — never overwrites a status you set yourself. See [Slack sync](#slack-sync). |
| 🪶 **Tiny & native** | Swift menu‑bar agent, no Dock icon, no Electron |

## Download

Get **`BizneoCompanion-<version>-macos-universal.dmg`** from the
[latest release](https://github.com/asolfre/bizneo-companion/releases/latest), open it
and drag **BizneoCompanion** onto **Applications**. (There's a `.zip` too: unzip it
and move the app to Applications.) Universal build (Apple silicon and Intel), macOS
13 or later; tested on Apple silicon only.

Bizneo Companion isn't notarized by Apple, so macOS blocks the first launch. Open it
once, then go to **System Settings → Privacy & Security** and click **Open Anyway**.
Or, in Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/BizneoCompanion.app
```

Then point it at your account (menu → **Settings…**) and allow the prompts described
under [Quick start](#quick-start).

**Updating:** quit the app, replace it in Applications, open it again. Every build is
a new app to macOS (it's ad-hoc signed), so after an update macOS asks again for the
Keychain (*Chrome Safe Storage*, and the Slack token if you set one): click **Always
Allow**. If it then says macOS is blocking access to Chrome's data, use **Reset
permission** in Settings → Account (see the [FAQ](#faq)).

## Quick start

> **Requirements:** macOS 13+, Google Chrome (logged in to Bizneo), and Xcode to
> build (the Command Line Tools alone can't build it any more) — or skip building
> and [download](#download) the app.

```bash
# 1) Build the app
./build_app.sh                      # → BizneoCompanion.app

# 2) Launch it
open BizneoCompanion.app

# 3) Point it at your account: menu → Settings…
#    set Tenant, User ID and your Chrome profile — see “Finding your details” below
```

The version shows in the menu header and in `BizneoCompanion.app/Contents/MacOS/BizneoCompanion --version`.
A build of a release tag shows just the version (`0.3.0`). Anything else shows the commit
it was built from (`0.3.0+d8c9728`, plus `.dirty` with uncommitted changes), so a
development build can't be mistaken for a release.

The first time it reads your cookie — and again after you change the Chrome profile
— macOS shows a Keychain prompt ("Chrome Safe Storage"). Click **Always Allow**.

On recent macOS (seen on 27) there's a second prompt: BizneoCompanion asks to access
**Google Chrome**'s data. Click **Allow**. You'll find it again under System Settings
→ Privacy & Security → **Files & Folders** → BizneoCompanion.

<details>
<summary><b>Finding your tenant &amp; user id</b></summary>

Open your Bizneo timesheet in Chrome. The URL looks like:

```
https://<your-company>.bizneohr.com/time-attendance/my-logs/<your-user-id>
```

- `tenant` = `<your-company>`
- `userId` = `<your-user-id>` (the number)
- `chromeProfile` = the Chrome profile you're logged in with (e.g. `Default`,
  `Profile 1`). Settings lists your profiles and marks the one with a Bizneo login;
  otherwise find it at `chrome://version` → *Profile Path*.

Then click **Test connection** in Settings → Account to check all three before saving.
</details>

## Using it day to day

- **The bar number** is your balance for the chosen period (`barMetric`, default
  `week`). **Red = behind, green = ahead.** Week/month/year are cumulative, so the
  bar reflects extra time you banked earlier in the period.
- **The dropdown** breaks it down by today / week / month / year. When unapproved
  edits exist you'll see `(official …, +… pending)` so you know what's provisional.
- **Clock controls** appear based on your current state: *Check in* when you're out,
  *Take break / Check out* while working, *Resume / Check out* on a break.
- **The bar icon tells you what the clock is doing** — and shouts when you've
  forgotten to start it:

  | Icon | Meaning | Bar shows |
  |---|---|---|
  | ▶︎ | Clocked in, timer running | your balance, ticking |
  | ⏸ | On a break | your balance, frozen |
  | ⏰ **orange** | **Not clocked in and you owe hours today** | **`Check in`** |
  | ◼︎ | Checked out before hitting today's target | your balance |
  | ✓ | Checked out, today complete | your balance |
  | *(none)* | Weekend, holiday or a "Fridom" day off | your balance, dimmed |

  Only the "not clocked in" state is coloured, and it's the only one that replaces
  the number — so a forgotten check-in can't hide behind a healthy weekly total.

## Privacy & security

- 🔒 **Local only.** Everything runs on your Mac and talks directly to your Bizneo
  tenant. No third‑party servers.
- 🙅 **No password stored.** It never asks for or keeps your Bizneo password — it
  reuses the session cookie Chrome already has.
- 🔑 **Cookie stays in memory.** Read fresh each refresh, never written to disk.
- 📍 **No location/geolocation** is ever sent when clocking in.

## Configuration

Menu → **Settings…** (⌘, while the menu is open) edits every option in a grouped form
and applies changes immediately — no restart. It also carries an **Open at login**
toggle, which is a system login item rather than a config field; for that to survive
reliably, keep `BizneoCompanion.app` in `/Applications` (`SMAppService` registers the
app at whatever path it's running from). If macOS has blocked it, the toggle offers
**Approve in System Settings…**. Changing the default project also replaces the one
last picked from **Check in ▸**.

The **Account** section helps you get connected. **Chrome profile** lists Chrome's
profiles by name, signed-in account and folder (`Work — you@company.com (Profile 3)`),
and marks the ones holding a Bizneo login for the tenant you typed as
**Bizneo session**. A marked profile's login may still have expired, so **Test
connection** checks the values in the form, before you save, with the same two
requests a refresh starts with. It reports *Connected* with your clock state, or the
exact problem: no cookie for that tenant in that profile, not logged in, or an
unknown User ID (Bizneo answers 404). With a manual cookie set it says so, since Chrome
isn't used then. The first test may show the "Chrome Safe Storage" Keychain prompt.
If macOS blocks access to Chrome's data, the section says so and offers **Open
Privacy & Security…** and **Reset permission** (see the [FAQ](#faq)).

Settings writes to `~/Library/Application Support/BizneoCompanion/config.json`, still
editable by hand if you prefer (Settings → *Advanced* → **Open config file…**).
Highlights:

| Key | What it does | Default |
|---|---|---|
| `barMetric` | Which period the bar shows: `today`/`week`/`month`/`year` | `week` |
| `enableYearTotal` | Show year‑to‑date (caches past months) | `true` |
| `defaultTelework` | Clock in/resume as telework | `true` |
| `defaultProjectId` | Project for the quick check‑in | `null` |
| `dayOffScheduleNames` | Schedule names that mean "day off" | `["Fridom", "Fridom (7 hours)"]` |
| `includePending` | Fold in unapproved change requests | `true` |
| `liveTick` | Count balances up each second while the timer runs | `true` |
| `barShowSecondsWhileWorking` | Show seconds (`H:MM:SS`) in the menu bar while working | `false` |
| `dropdownSecondsScope` | Which dropdown rows tick in seconds: `none`/`today`/`all` | `today` |
| `leaveByScope` | Which backlog "Leave by" clears: `none`/`week`/`month`/`year` | `none` |
| `refreshSeconds` | Auto‑refresh interval | `600` |
| `remindersEnabled` | Check‑in reminders on/off (keeps the windows when off) | `true` |
| `reminderWindows` | When reminders may fire, Madrid time, `HH:MM-HH:MM` | `["08:00-10:00", "14:00-15:30"]` |
| `reminderIntervalMinutes` | Minutes between reminders inside a window | `15` |

<details><summary>Full config example</summary>

```json
{
  "tenant": "<your-company>",
  "userId": "<your-user-id>",
  "chromeProfile": "Default",
  "refreshSeconds": 600,
  "weekStartsMonday": true,
  "includePending": true,
  "dayOffScheduleNames": ["Fridom", "Fridom (7 hours)"],
  "enableClockActions": true,
  "enableYearTotal": true,
  "barMetric": "week",
  "defaultTelework": true,
  "defaultProjectId": null,
  "liveTick": true,
  "barShowSecondsWhileWorking": false,
  "dropdownSecondsScope": "today",
  "leaveByScope": "none",
  "remindersEnabled": true,
  "reminderWindows": ["08:00-10:00", "14:00-15:30"],
  "reminderIntervalMinutes": 15,
  "manualCookie": null
}
```
</details>

### Slack sync

Optional, off by default. Settings → **Slack** mirrors your clock into Slack:

| Bizneo | Status | Presence |
|---|---|---|
| Working | 💻 Working | auto (green when active) |
| On a break | ☕ On a break | away |
| Checked out / not in / day off | cleared | away |

Pick what it updates with **Update**:

| Mode | Updates | Token scopes needed |
|---|---|---|
| Presence *(default)* | presence only, even while you have a manual status | `users:write` |
| Status | status only, presence never touched | `users.profile:read`, `users.profile:write` |
| Status & presence | both | `users.profile:read`, `users.profile:write`, `users:write` |

A status you set yourself (🌴 Vacation, 📅 In a meeting) is never replaced. Statuses
expire after two refresh intervals and are renewed while you work, so quitting the
app or sleeping the Mac lets Slack clear them. Presence has no expiry, so quitting
the app (or logging out) sets it back to auto; only a crash or force-quit can leave
you on away, until the app next runs. Switching the sync off clears ours and
sets presence back to auto.

**Getting a token** (about 5 minutes):

1. Go to <https://api.slack.com/apps> → **Create New App** → **From scratch**; name it
   (e.g. "Bizneo Companion") and pick your workspace.
2. **OAuth & Permissions** → **Scopes** → under **User Token Scopes** (not *Bot
   Token Scopes*) add the scopes for your mode from the table above — for the
   default (Presence) that's just `users:write`.
3. Top of **OAuth & Permissions** → **Install to Workspace** → **Allow**. If you only
   see *Request to Install*, a workspace admin has to approve it first.
4. Copy the **User OAuth Token** (`xoxp-…`). Not the bot token (`xoxb-…`): it can't
   change your own status.
5. Settings → **Slack**: paste it, switch on **Sync to Slack**, pick a mode, **Save**.

The token goes to the macOS Keychain, never `config.json`. The first read shows a
Keychain prompt: click **Always Allow** (a rebuilt app may ask again). Adding scopes
later means reinstalling the Slack app; if it shows a new token, paste it again. To
revoke: **Clear** + **Save** in Settings, or remove the app in Slack.

## FAQ

**Do I need an API token or admin access?** No — it reuses your normal Chrome login.

**Will it change my data?** Only when *you* click a clock action. The balance views
are read‑only.

**It says "Not logged in"?** Your Bizneo session expired — open Bizneo in Chrome and
log in; the app picks the new cookie up on the next refresh.

**It says "macOS is blocking access to Chrome's data"?** Recent macOS (seen on 27)
asks before an app reads another app's data. Allow **Google Chrome** under
BizneoCompanion in Privacy & Security → **Files & Folders** (the menu's **Open
Privacy & Security…** goes there). macOS ties that permission to one build of the
app, so after installing a different build the toggle may keep switching itself off.
Then use **Reset permission** in Settings → Account (or run
`tccutil reset All com.asolfre.bizneocompanion` in Terminal), quit and reopen the
app, and click **Allow** when asked. The reset only clears macOS privacy decisions for
this app; notifications, open at login and Keychain access stay as they are. Running
`--probe` from Terminal reads Chrome as Terminal, so Terminal needs the access then.

**Does it work with Safari/Firefox?** Currently Chrome only. (Or paste a cookie via
`manualCookie`.)

## How it works

<details><summary>Architecture &amp; endpoints (for the curious)</summary>

Bizneo Companion authenticates by decrypting Chrome's `_hcmex_key` session cookie
(Keychain *Chrome Safe Storage* + AES‑128‑CBC) and calling the same internal
endpoints the web app uses, parsing the returned HTML.

| Figure | Source |
|---|---|
| Today | `GET /chrono/{userId}/hub_chrono` → scheduled / logged |
| Month | `GET /time-attendance/my-logs/{userId}?month=&year=` → balance "Until today" |
| Week | same page → sum of daily balances |
| Year | sum of monthly pages Jan→now (past months cached) |
| Pending | `…/logged-time-requests/{id}` → proposed duration |

Clock actions: `POST /chrono` (check in), `PUT /chrono/{userId}` with `pause=` to
break/resume and without it to check out.

Parsers are anchored on stable labels/classes and covered by a built‑in self‑test
against captured HTML fixtures:

```bash
BizneoCompanion.app/Contents/MacOS/BizneoCompanion \
  --selftest Tests/BizneoCompanionTests/Fixtures
```

Project layout: `Sources/BizneoCore` (parsing, models, client, cookie decrypt),
`Sources/BizneoCompanion` (menu‑bar UI, probe, self‑test).
</details>

## Roadmap

- [ ] Real screenshots / demo GIF
- [ ] Optional telework/office quick toggle
- [ ] Manual "refresh year" for late approvals in past months
- [ ] Safari/Firefox cookie support

## Contributing

Issues and PRs welcome — especially if Bizneo changes its markup (re‑capture the
HTML and update `TimesheetParser`). If this saved you some clicks, a ⭐ helps others find it.

## License

Licensed under [Creative Commons Attribution‑NonCommercial 4.0 International](LICENSE)
(CC BY‑NC 4.0) © 2026 **asolfre**. You may share and adapt it for non‑commercial
purposes with attribution.

## Disclaimer

Independent, unofficial tool. Not affiliated with or endorsed by Bizneo. It uses
undocumented internal endpoints that may change at any time. Use at your own risk.
