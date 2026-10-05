import Foundation
import Cocoa
import BizneoCore

// Entry point. Two modes:
//   • default            → run the menu-bar agent
//   • --probe / --once   → fetch once, print a text report, exit (for validation from Terminal)
//   • --dump             → (with --probe) also write raw HTML of each endpoint to /tmp for debugging
//   • --version / -v     → print the version and exit

let args = Set(CommandLine.arguments.dropFirst())

if let idx = CommandLine.arguments.firstIndex(of: "--selftest") {
    let dir = CommandLine.arguments.count > idx + 1 ? CommandLine.arguments[idx + 1]
        : "Tests/BizneoCompanionTests/Fixtures"
    exit(Int32(SelfTest.run(dir: dir)))
}

if args.contains("--version") || args.contains("-v") {
    print("\(AppInfo.name) \(AppInfo.version)")
    exit(0)
}

if args.contains("--probe") || args.contains("--once") {
    Probe.run(dump: args.contains("--dump"))
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon (equivalent to LSUIElement)

// Never displayed (accessory apps don't own the menu bar), but AppKit routes ⌘X/C/V/A/Z
// through the main menu's key equivalents — without it, paste is dead in Settings.
let editMenu = NSMenu(title: "Edit")
editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
editMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
let editItem = NSMenuItem()
editItem.submenu = editMenu
app.mainMenu = NSMenu()
app.mainMenu?.addItem(editItem)

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: StatusItemController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let c = StatusItemController(config: Config.load())
            self.controller = c
            c.start()
        }
    }
}
let delegate = AppDelegate()
app.delegate = delegate
app.run()
