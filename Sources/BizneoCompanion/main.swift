import Foundation
import Cocoa
import BizneoCore

// Entry point. Two modes:
//   • default            → run the menu-bar agent
//   • --probe / --once   → fetch once, print a text report, exit (for validation from Terminal)
//   • --dump             → (with --probe) also write raw HTML of each endpoint to /tmp for debugging

let args = Set(CommandLine.arguments.dropFirst())

if let idx = CommandLine.arguments.firstIndex(of: "--selftest") {
    let dir = CommandLine.arguments.count > idx + 1 ? CommandLine.arguments[idx + 1]
        : "Tests/BizneoCompanionTests/Fixtures"
    exit(Int32(SelfTest.run(dir: dir)))
}

if args.contains("--probe") || args.contains("--once") {
    Probe.run(dump: args.contains("--dump"))
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon (equivalent to LSUIElement)

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
