// Regenerates the README images in docs/ from `--demo` (anonymized fixtures, no
// network). From the repo root, after `swift build`:
//
//     swift docs/screenshots.swift
//
// The terminal needs Accessibility and Screen Recording. Menus are opened and items
// picked through Accessibility, never with keystrokes, and windows are captured by
// id, so nothing else on screen ends up in an image. The system appearance flips to
// light and dark and is restored at the end. Images come out at the scale of the
// display holding the active menu bar: use a Retina one.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let docs = "docs/"

@discardableResult
func run(_ path: String, _ args: [String], wait: Bool = true) -> (Process, String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = wait ? pipe : FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try! p.run()
    guard wait else { return (p, "") }
    let out = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p, String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
}

@discardableResult
func osa(_ script: String, wait: Bool = true) -> String { run("/usr/bin/osascript", ["-e", script], wait: wait).1 }
func pause(_ s: Double) { Thread.sleep(forTimeInterval: s) }

let appearance = #"tell application "System Events" to tell appearance preferences to"#
let wasDark = osa("\(appearance) get dark mode") == "true"
func setDark(_ on: Bool) { osa("\(appearance) set dark mode to \(on)"); pause(1.5) }

var demo: Process?
func fail(_ message: String) -> Never {
    print("✗ \(message)")
    demo?.terminate()
    setDark(wasDark)
    exit(1)
}

func waitFor(_ what: String, _ done: () -> Bool) {
    for _ in 0..<80 {
        if done() { return }
        pause(0.1)
    }
    fail("timed out waiting for \(what)")
}

struct Win { let id: Int; let layer: Int; let frame: CGRect }

func windows(_ pid: Int32) -> [Win] {
    let all = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    return all.compactMap { w in
        guard (w[kCGWindowOwnerPID as String] as? Int32) == pid,
              let id = w[kCGWindowNumber as String] as? Int,
              let layer = w[kCGWindowLayer as String] as? Int,
              let bounds = w[kCGWindowBounds as String],
              let frame = CGRect(dictionaryRepresentation: bounds as! CFDictionary) else { return nil }
        return Win(id: id, layer: layer, frame: frame)
    }
}

/// A running `--demo`, driven through System Events.
struct Session {
    let pid: Int32
    var tell: String { "tell application \"System Events\" to tell (first process whose unix id is \(pid)) to" }
    let item = "menu bar item 1 of menu bar 2"
    var menu: Win? { windows(pid).first { $0.layer == 101 } }
    /// Settings (layer 0) or the check-out alert (a modal panel, layer 8).
    var window: Win? { windows(pid).first { $0.layer != 101 } }

    /// The status item has no window of its own (the Window Server draws it into the
    /// menu bar), so it's captured as this rectangle of the screen.
    var itemFrame: CGRect {
        var v: [Double] = []
        waitFor("the status item's frame") {
            v = osa("\(tell) get {position, size} of \(item)").split(separator: ",")
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            return v.count == 4
        }
        return CGRect(x: v[0], y: v[1], width: v[2], height: v[3])
    }

    func row(_ prefix: String) -> String {
        "(first menu item of menu 1 of \(item) whose name starts with \"\(prefix)\")"
    }
    func open() {
        osa("\(tell) click \(item)", wait: false)
        waitFor("the menu") { menu != nil }
        pause(0.4)
    }
    func close() {
        osa("\(tell) perform action \"AXCancel\" of menu 1 of \(item)")
        waitFor("the menu to close") { menu == nil }
    }
    func highlight(_ prefix: String) {
        osa("\(tell) set value of attribute \"AXSelected\" of \(row(prefix)) to true")
        pause(0.3)
    }
    func choose(_ prefix: String) {
        osa("\(tell) click \(row(prefix))", wait: false)
        waitFor("\(prefix)") { menu == nil }
        pause(0.8)
    }
}

func launch(_ state: String) -> Session {
    demo?.terminate()
    demo?.waitUntilExit()
    let p = run(".build/debug/BizneoCompanion", ["--demo", state], wait: false).0
    demo = p
    let s = Session(pid: p.processIdentifier)
    waitFor("the status item") { !osa("\(s.tell) get description of \(s.item)").isEmpty }
    pause(0.5)
    return s
}

func capture(_ args: [String]) -> CGImage {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".png")
    run("/usr/sbin/screencapture", ["-x"] + args + [tmp.path])
    defer { try? FileManager.default.removeItem(at: tmp) }
    guard let data = try? Data(contentsOf: tmp),
          let src = CGImageSourceCreateWithData(data as CFData, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else { fail("screencapture failed: does the terminal have Screen Recording?") }
    return img
}
func shot(_ w: Win) -> CGImage { capture(["-l\(w.id)"]) }   // with its shadow, on transparency
func shot(_ r: CGRect) -> CGImage { capture(["-R", "\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height))"]) }

// Menus are glass: captured alone, a light one has nothing to blur and comes out flat
// grey. So they're shot over a plain window in GitHub's page colour, which is also
// what the README shows around them.
NSApplication.shared.setActivationPolicy(.accessory)
let backdrop = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
backdrop.hasShadow = false
backdrop.ignoresMouseEvents = true
let githubDark = NSColor(srgbRed: 13 / 255, green: 17 / 255, blue: 23 / 255, alpha: 1)

/// `w` and its shadow, over the backdrop. Level 30 covers the menu bar but stays
/// under menus (101); an alert (8) needs one below it.
func onBackdrop(_ w: Win, dark: Bool, level: Int = 30) -> (CGImage, CGRect) {
    let r = CGRect(x: w.frame.minX - 40, y: w.frame.minY - 24, width: w.frame.width + 80, height: w.frame.height + 80)
    let top = NSScreen.screens[0].frame.maxY   // Cocoa's origin is bottom-left, CG's top-left
    backdrop.level = NSWindow.Level(rawValue: level)
    backdrop.backgroundColor = dark ? githubDark : .white
    backdrop.setFrame(NSRect(x: r.minX, y: top - r.maxY, width: r.width, height: r.height), display: true)
    backdrop.orderFrontRegardless()
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    defer {
        backdrop.orderOut(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    return (shot(r), r)
}

func save(_ img: CGImage, _ name: String) {
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: docs + name) as CFURL,
                                            UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, nil)
    CGImageDestinationFinalize(d)
    print("✓ docs/\(name)  \(img.width)×\(img.height)")
}

// MARK: - Stills, in both appearances

for (dark, suffix) in [(false, "light"), (true, "dark")] {
    setDark(dark)
    var s = launch("working")
    s.open()
    save(onBackdrop(s.menu!, dark: dark).0, "menu-\(suffix).png")
    s.close()

    s = launch("not-checked-in")
    // The menu bar follows the wallpaper, not the appearance: one capture does.
    if !dark { save(shot(s.itemFrame), "checkin-bar.png") }
    s.open()
    save(onBackdrop(s.menu!, dark: dark).0, "not-checked-in-\(suffix).png")
    s.choose("Settings")
    waitFor("Settings") { s.window != nil }
    pause(1)
    save(shot(s.window!), "settings-\(suffix).png")
}

// MARK: - demo.gif (light): check in → break → resume → check out, back to the start

setDark(false)
struct Frame { let bar: CGImage; let barAt: CGRect; var over: CGImage?; var overAt: CGRect?; let delay: Double }
var frames: [Frame] = []
let s = launch("not-checked-in")
func still(_ delay: Double, over: (CGImage, CGRect)? = nil) {
    let bar = s.itemFrame
    frames.append(Frame(bar: shot(bar), barAt: bar, over: over?.0, overAt: over?.1, delay: delay))
}
still(1.5)
for row in ["Check in ·", "Take break", "Resume", "Check out"] {
    s.open()
    s.highlight(row)
    still(1.2, over: onBackdrop(s.menu!, dark: false))
    s.choose(row)
    if row == "Check out" {
        waitFor("the confirmation") { s.window != nil }
        pause(0.5)
        // The alert opens mid-screen; the GIF shows it under the bar item.
        let (img, r) = onBackdrop(s.window!, dark: false, level: 7)
        let bar = s.itemFrame
        still(1.8, over: (img, CGRect(origin: CGPoint(x: (bar.midX - r.width / 2).rounded(), y: bar.maxY), size: r.size)))
        osa("\(s.tell) click button \"Check out\" of window 1")
        waitFor("the confirmation to close") { s.window == nil }
        pause(0.8)
    }
    still(row == "Check out" ? 1.5 : 1.0)
}
demo?.terminate()

// Composed at 1x on white, like the backdrop, so the frames are seamless.
let barTop = frames.map(\.barAt.minY).min()!
var area = frames.reduce(CGRect.null) { $0.union($1.barAt).union($1.overAt ?? .null) }.insetBy(dx: -12, dy: -12)
area = CGRect(x: area.minX, y: barTop, width: area.width, height: area.maxY - barTop).integral
let gif = CGImageDestinationCreateWithURL(URL(fileURLWithPath: docs + "demo.gif") as CFURL,
                                          UTType.gif.identifier as CFString, frames.count, nil)!
CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]] as CFDictionary)
for f in frames {
    let ctx = CGContext(data: nil, width: Int(area.width), height: Int(area.height), bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setFillColor(.white)
    ctx.fill(CGRect(origin: .zero, size: area.size))
    // Screen points have a top-left origin, the context a bottom-left one.
    func draw(_ img: CGImage, in r: CGRect) {
        ctx.draw(img, in: CGRect(x: r.minX - area.minX, y: area.maxY - r.maxY, width: r.width, height: r.height))
    }
    if let o = f.over, let r = f.overAt { draw(o, in: r) }
    // The bar is see-through, so the item comes with a scrap of wallpaper: stretch
    // its edge columns across the frame to make it a menu bar again.
    let b = f.barAt, h = f.bar.height
    draw(f.bar.cropping(to: CGRect(x: 0, y: 0, width: 1, height: h))!,
         in: CGRect(x: area.minX, y: b.minY, width: b.minX - area.minX, height: b.height))
    draw(f.bar.cropping(to: CGRect(x: f.bar.width - 1, y: 0, width: 1, height: h))!,
         in: CGRect(x: b.maxX, y: b.minY, width: area.maxX - b.maxX, height: b.height))
    draw(f.bar, in: b)   // last: the menu's backdrop reaches into the bar
    CGImageDestinationAddImage(gif, ctx.makeImage()!,
                               [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: f.delay]] as CFDictionary)
}
CGImageDestinationFinalize(gif)
print("✓ docs/demo.gif  \(Int(area.width))×\(Int(area.height)), \(frames.count) frames")

setDark(wasDark)
