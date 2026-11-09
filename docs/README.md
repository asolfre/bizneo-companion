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
otherwise. It also switches the system appearance to light and dark for about a
minute, then restores it.

- The terminal needs **Accessibility** and **Screen Recording**.
- Images come out at the scale of the display holding the active menu bar, so use a
  Retina one for sharp images. The README sets each width in points, so 1x and 2x
  captures both fit.

| File | Shows |
|---|---|
| `menu-light.png`, `menu-dark.png` | `--demo working`, menu open (README top) |
| `checkin-bar.png` | The orange **Check in** item. The menu bar follows the wallpaper, not the appearance, so there's one. |
| `not-checked-in-light.png`, `-dark.png` | `--demo not-checked-in`, menu open |
| `settings-light.png`, `-dark.png` | The Settings window with the demo's placeholder account |
| `demo.gif` | Check in → Take break → Resume → Check out, light only |

## `--demo`

`swift run BizneoCompanion --demo <state>` from the repo root shows any clock state
on the spot: `working`, `break`, `not-checked-in`, `checked-out`, `done`, `off` or
`unknown`. Nothing leaves the process: clock actions only change the state in memory,
**Refresh now** does nothing, Settings reads neither Chrome nor the Keychain and never
saves, and the last-used project is neither read nor written.
