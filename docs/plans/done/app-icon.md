# Plan: An app icon

*Planned in conversation and implemented in the same branch; no pending stage.*

## Problem

The bundle had no icon: `build_app.sh` created an empty `Contents/Resources/`, and
the `Info.plist` named none. So the reminder notifications, Finder, the release DMG,
and System Settings (Login Items, Privacy & Security) all showed a generic blank
icon. `checkout-alert-icon.md` had left a real icon out of scope because it needs
artwork.

## Design

- **Source: `AppIcon.svg`** at the repo root, hand-written text, with no binary in
  the repo.
  - macOS renders SVG natively (`_NSSVGImageRep`), and `sips` with it.
  - `build_app.sh` renders the ten iconset sizes (16 to 512, each at 1x and 2x) and
    runs `iconutil -c icns` into `Contents/Resources/AppIcon.icns`. It also adds
    `CFBundleIconFile` = `AppIcon` to the `Info.plist`.
  - Both tools ship with macOS, so CI and the release workflow need nothing new.
- **Artwork: a progress clock.** A clock at 10:00 inside a green ring that is 78 %
  full, meaning today's target filling up. It sits on a light squircle on Apple's
  macOS grid: an 824-pt body in a 1024 canvas, corner radius 185.
  - **Picked from three mockups:** a stopwatch, a balance gauge (red − to green +),
    and this one.
  - **No SF Symbols:** Apple's licence forbids them, or anything confusingly
    similar, in app icons, so the shapes are drawn from scratch.
  - **Nothing like Bizneo's logo,** since the app is unofficial.
- **The shadow is drawn by hand.** `sips`'s SVG renderer ignores filters (checked:
  a `feDropShadow` left the pixels under the shape fully transparent). So the
  shadow is three offset translucent rounded rectangles, plus a faint outline.
- **macOS 27 masks the artwork itself.** It applies its own continuous-corner shape
  and glass edge, which clips that shadow away; earlier versions show the icon as
  drawn, shadow included. It doesn't put the icon in a grey frame, which recent
  macOS does for icons it considers non-conforming.
- **The README title** shows the SVG in place of the ⏱️ emoji.

## Rejected design

- **An Icon Composer `.icon` compiled with `actool`.** It's the native format for
  macOS 26 and later, but it's a GUI-authored bundle built for Xcode projects, and
  this app is SwiftPM plus a shell script. macOS 27 already gives the `.icns` the
  system treatment.
- **A committed `AppIcon.icns`.** It would be a 430 KB binary that can drift from
  its source. Rendering at build time takes half a second.

## Verification

- `./build_app.sh`:
  - `Contents/Resources/AppIcon.icns` is present, and `CFBundleIconFile` reads
    `AppIcon`.
  - `codesign -dv` lists the one sealed resource.
- `NSWorkspace.icon(forFile:)` on the built app renders the icon at 512 px and
  32 px on macOS 27, with no grey frame, and it's still readable at 32 px.
