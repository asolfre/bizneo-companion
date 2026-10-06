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
| 🪶 **Tiny & native** | Swift menu‑bar agent, no Dock icon, no Electron |

## Quick start

> **Requirements:** macOS 13+, Google Chrome (logged in to Bizneo), and Apple's
> Command Line Tools (`xcode-select --install`).

```bash
# 1) Build the app
./build_app.sh                      # → BizneoCompanion.app

# 2) Launch it
open BizneoCompanion.app

# 3) Point it at your account: menu → Settings…
#    set Tenant, User ID and your Chrome profile — see “Finding your details” below
```

The first time it reads your cookie — and again after you change the Chrome profile
— macOS shows a Keychain prompt ("Chrome Safe Storage"). Click **Always Allow**.

<details>
<summary><b>Finding your tenant &amp; user id</b></summary>

Open your Bizneo timesheet in Chrome. The URL looks like:

```
https://<your-company>.bizneohr.com/time-attendance/my-logs/<your-user-id>
```

- `tenant` = `<your-company>`
- `userId` = `<your-user-id>` (the number)
- `chromeProfile` = the Chrome profile you're logged in with (e.g. `Default`,
  `Profile 1`). Find it at `chrome://version` → *Profile Path*.
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

## FAQ

**Do I need an API token or admin access?** No — it reuses your normal Chrome login.

**Will it change my data?** Only when *you* click a clock action. The balance views
are read‑only.

**It says "Not logged in"?** Your Bizneo session expired — open Bizneo in Chrome and
log in; the app picks the new cookie up on the next refresh.

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
