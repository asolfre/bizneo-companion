// Composes docs/social-preview.png, the 1280×640 card GitHub shows when the repo is
// shared, from AppIcon.svg and the README's menu screenshot. From the repo root:
//
//     swift docs/social-preview.swift
//
// GitHub has no API for it: upload the PNG in Settings → General → Social preview.
import AppKit

// The menu screenshot sits on GitHub's dark page colour, so the card uses the same one.
let background = NSColor(srgbRed: 13 / 255, green: 17 / 255, blue: 23 / 255, alpha: 1)
let ink = NSColor.white
let muted = NSColor(srgbRed: 0.62, green: 0.66, blue: 0.70, alpha: 1)

guard let icon = NSImage(contentsOfFile: "AppIcon.svg"),
      let menu = NSImage(contentsOfFile: "docs/menu-dark.png") else {
    print("✗ run from the repo root, after `swift docs/screenshots.swift`")
    exit(1)
}

let size = NSSize(width: 1280, height: 640)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
background.setFill()
NSRect(origin: .zero, size: size).fill()

// Right: the menu, as tall as the card allows (the screenshot carries its own margin).
let menuHeight: CGFloat = 600
let menuWidth = menuHeight * menu.size.width / menu.size.height
menu.draw(in: NSRect(x: size.width - menuWidth - 16, y: (size.height - menuHeight) / 2,
                     width: menuWidth, height: menuHeight))

// Left: icon, name, tagline, footer. AppKit's origin is bottom-left.
let left: CGFloat = 72, column: CGFloat = 600
icon.draw(in: NSRect(x: left - 22, y: 400, width: 170, height: 170))   // the SVG has a 10 % margin
func text(_ s: String, _ font: NSFont, _ color: NSColor, top: CGFloat, spacing: CGFloat = 0) {
    let style = NSMutableParagraphStyle()
    style.lineSpacing = spacing
    let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    let h = a.boundingRect(with: NSSize(width: column, height: 400), options: .usesLineFragmentOrigin).height
    a.draw(with: NSRect(x: left, y: size.height - top - h, width: column, height: h), options: .usesLineFragmentOrigin)
}
text("Bizneo Companion", .systemFont(ofSize: 64, weight: .bold), ink, top: 262)
text("Your Bizneo time balance, live in the macOS menu bar, with one‑click clock in/out.",
     .systemFont(ofSize: 30, weight: .regular), muted, top: 352, spacing: 6)
text("macOS 13+  ·  free  ·  github.com/asolfre/bizneo-companion",
     .systemFont(ofSize: 21, weight: .medium), muted, top: 548)

NSGraphicsContext.restoreGraphicsState()
let out = "docs/social-preview.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("✓ \(out)")
