import Foundation
import BizneoCore

/// Command-line validation mode: fetch once, print a human-readable report, and
/// optionally dump raw HTML for debugging. Run with `--probe` (and `--dump`).
enum Probe {
    static func run(dump: Bool) {
        let config = Config.load()
        FileHandle.standardError.write(Data("Using tenant=\(config.host) user=\(config.userId) profile=\(config.chromeProfile)\n".utf8))
        let client = BizneoClient(config: config)
        let sem = DispatchSemaphore(value: 0)

        Task {
            defer { sem.signal() }
            if dump { await dumpRaw(config: config, client: client) }
            do {
                let snap = try await client.refresh()
                printReport(snap)
            } catch {
                let msg = (error as? BizneoError)?.errorDescription ?? error.localizedDescription
                print("\nERROR: \(msg)")
                if case .some(.notAuthenticated) = error as? BizneoError {
                    print("→ Open https://\(config.host)/ in Chrome (Profile 3) and log in, then retry.")
                }
            }
        }
        sem.wait()
    }

    static func printReport(_ s: Snapshot) {
        func line(_ p: PeriodStat) {
            let verb = p.projectedBalanceMin < 0 ? "missing" : "ahead "
            var str = String(format: "  %-11@  %@ %@", p.label as NSString, verb, TimeFmt.plain(abs(p.projectedBalanceMin)))
            if p.hasPending {
                str += "   [official \(TimeFmt.signed(p.officialBalanceMin)) + pending \(TimeFmt.signed(p.pendingDeltaMin))]"
            }
            print(str)
        }
        print("\n=== Bizneo time balance (incl. pending) ===")
        line(s.today); line(s.week); line(s.month)
        if let y = s.year { line(y) }
        if let c = s.chrono {
            let when = c.startedAt.map { " (since \($0))" } ?? ""
            print("  Clock: \(c.status.rawValue)\(c.status == .stopped ? "" : when)")
        }
        if let ml = s.monthLoggedMin { print("  Month logged so far: \(TimeFmt.plain(ml))") }
        if !s.pending.isEmpty {
            print("\nPending change requests:")
            for p in s.pending.sorted(by: { $0.dateString < $1.dateString }) {
                let proposed = p.proposedMin.map { TimeFmt.plain($0) } ?? "?"
                print("  \(p.dateString)  request \(p.id)  proposes \(proposed)  (Δ \(TimeFmt.signed(p.deltaMin)))  state=\(p.state ?? "?")")
            }
        }
        print("")
    }

    static func dumpRaw(config: Config, client: BizneoClient) async {
        let dir = URL(fileURLWithPath: "/tmp/bizneo-dump")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func write(_ name: String, _ s: String) {
            try? s.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
            FileHandle.standardError.write(Data("dumped /tmp/bizneo-dump/\(name) (\(s.count) bytes)\n".utf8))
        }
        if let h = try? await client.fetchHubChrono() { write("hub_chrono.html", h) }
        let now = Date()
        let cal = Calculator.madridCalendar(weekStartsMonday: config.weekStartsMonday)
        if let m = try? await client.fetchMonthLogs(month: cal.component(.month, from: now),
                                                    year: cal.component(.year, from: now)) {
            write("my_logs.html", m)
            for d in TimesheetParser.parseDays(m) where d.pendingRequestId != nil {
                if let id = d.pendingRequestId, let detail = try? await client.fetchRequestDetail(id: id) {
                    write("request_\(id).html", detail)
                }
            }
        }
    }
}
