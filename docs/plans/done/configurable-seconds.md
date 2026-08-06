# Plan: Configurable seconds display

Goal: make the live-tick seconds rendering configurable, with the **default being
"seconds only on the Today row"**, while allowing broader (all rows) or off.

## Background

- Live-tick currently renders the **Today** row in `H:MM:SS` (ticking each second
  while clocked in); Week/Month/Year show `H:MM`. This is hardcoded.
- Existing seconds controls in `Config`:
  - `liveTick: Bool = true` — master on/off for live ticking
  - `barShowSecondsWhileWorking: Bool = false` — seconds in the menu bar

## Decisions (confirmed)

- Default = **seconds on the Today row only**.
- Must be configurable to **broader** (all dropdown rows) and off.
- → A single bool can't express this; use an enum scope.

## Config (BizneoCore/Config.swift)

- Add enum:
  ```swift
  public enum DropdownSecondsScope: String, Codable { case none, today, all }
  ```
- Add field `dropdownSecondsScope: DropdownSecondsScope = .today`.
- Add a line to the tolerant decoder so old config.json still loads:
  ```swift
  dropdownSecondsScope = try c.decodeIfPresent(DropdownSecondsScope.self,
      forKey: .dropdownSecondsScope) ?? d.dropdownSecondsScope
  ```
- Resulting seconds controls:
  - `liveTick` (master)
  - `barShowSecondsWhileWorking` (menu bar)
  - `dropdownSecondsScope` (dropdown rows): `none` / `today` (default) / `all`

## StatusItemController.swift

- Keep the existing `isToday` / `secondsLive` plumbing (per-row flag in
  `periodRows`; `periodItem(_:isToday:)`).
- Gate seconds in `periodTitleString(_:secondsLive:)`:
  ```swift
  let showSeconds = isLive && {
      switch config.dropdownSecondsScope {
      case .none:  return false
      case .today: return secondsLive      // true only for the Today row
      case .all:   return true
      }
  }()
  let mag = showSeconds ? hmsMagnitude(secs) : TimeFmt.plain(abs(secs) / 60)
  ```
- `tick()` and `rebuildMenu` unchanged.

## Tests / build

- Presentation-only → existing self-test checks stay valid.
- Add: `check(Config().dropdownSecondsScope == .today, "default seconds scope == today")`.
- Rebuild BizneoCompanion.app.

## Status

- IMPLEMENTED (default `.today`), plus README config docs. Verified building +
  self-test passing.

## Notes

- Open naming question resolved to `dropdownSecondsScope` (values `none`/`today`/`all`).
