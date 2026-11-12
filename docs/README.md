# docs/

- **[`plans/`](plans/README.md)** — feature design docs (`plans/pending/` = not built
  yet, `plans/done/` = shipped).
- Product images live directly in this folder — see below.

## Images

The README's images all come from `--demo`, which draws the real menu from the
anonymized test fixtures. A script captures them; re-run it after any UI change:

```bash
swift build && swift docs/screenshots.swift
```

It opens the demo's menus and picks items through Accessibility (no keystrokes) and
captures windows by id, so nothing else on screen ends up in an image. Menus are shot
over a plain window in GitHub's page colour, since their glass has nothing to blur
otherwise. For about a minute and a half it switches the system appearance to light
and dark and parks the pointer in a corner, so it can't highlight a row; it restores
both at the end.

- The terminal needs **Accessibility** and **Screen Recording**.
- Images come out at the scale of the display holding the active menu bar, and the
  script stops unless that's a Retina one: click on that screen first. The README
  sets each width in points, so the 2x images show at the right size.
- On a notched screen, a full menu bar hides the demo's item behind the notch. The
  script stops if so: quit a few menu-bar apps for the run, the installed Bizneo
  Companion included.
- Images don't depend on when they're taken: the demo's clock is fixed at 10:00 and
  its menus show no version, so a re-shoot only changes what the UI changed.
- **`archive/`** (git-ignored, local only) keeps earlier image sets, one folder per
  run. Copy the current images there before a re-shoot if you want to keep them.

| File | Shows |
|---|---|
| `menu-light.png`, `menu-dark.png` | `--demo working`, menu open (README top) |
| `checkin-bar.png` | The orange **Check in** item. The menu bar follows the wallpaper, not the appearance, so there's one. |
| `not-checked-in-light.png`, `-dark.png` | `--demo not-checked-in`, menu open |
| `settings-light.png`, `-dark.png` | The Settings window with the demo's placeholder account |
| `demo.gif` | Check in → Take break → Resume → Check out, light only |
| `social-preview.png` | The 1280×640 card GitHub shows when the repo is shared: icon, name, tagline and `menu-dark.png`. Composed by `swift docs/social-preview.swift` (re-run it after the screenshots). GitHub has no API for it: upload it in **Settings → General → Social preview**. |

## `--demo`

`swift run BizneoCompanion --demo <state>` from the repo root shows any clock state
on the spot: `working`, `break`, `not-checked-in`, `checked-out`, `done`, `off` or
`unknown`. Nothing leaves the process: clock actions only change the state in memory,
**Refresh now** does nothing, Settings reads neither Chrome nor the Keychain and never
saves, and the last-used project is neither read nor written. The clock reads 10:00
and the version is left out of the menu and Settings, so screenshots outlive both the
time of day and the next release.
