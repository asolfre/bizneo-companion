import Foundation
import BizneoCore

/// `--demo <state>`: the real menu, drawn from the anonymized test fixtures instead
/// of Bizneo. For README screenshots, and for seeing every clock state without
/// waiting for it. Nothing leaves the process: no network, no Chrome, no Keychain,
/// clock actions only change the state in memory, and Settings never saves.
/// Reads `Tests/BizneoCompanionTests/Fixtures`, so run it from the repo root.
enum Demo {
    static let isActive = CommandLine.arguments.contains("--demo")

    static let states = ["working", "break", "not-checked-in", "checked-out", "done", "off", "unknown"]

    /// Placeholder account, so Settings looks filled in. Project D is a fixture project.
    static let config = Config(tenant: "acme", userId: "123456", defaultProjectId: "15741264")

    /// The fixtures as of Thu 18 Jun 2026 12:00 (as in `SelfTest`), timestamped `now`
    /// so the live tick and "Leave by" run on the real clock. nil for an unknown state
    /// or missing fixtures.
    static func snapshot(_ state: String, dir: String = "Tests/BizneoCompanionTests/Fixtures",
                         now: Date = Date()) -> Snapshot? {
        let base = URL(fileURLWithPath: dir)
        func load(_ name: String) -> String? {
            try? String(contentsOf: base.appendingPathComponent(name), encoding: .utf8)
        }
        let chronoFile = switch state {
        case "working": "chrono_working.html"
        case "break": "chrono_paused.html"
        default: "chrono_stopped.html"
        }
        guard states.contains(state), let hub = load("hub_chrono.html"), let logs = load("my_logs.html"),
              let chronoHTML = load(chronoFile) else { return nil }

        let cal = Calculator.madridCalendar(weekStartsMonday: config.weekStartsMonday)
        let pending = [
            PendingRequest(id: "1275258", dateString: "2026-06-15", proposedMin: 8*60+14, currentLoggedMin: 355),
            PendingRequest(id: "1283627", dateString: "2026-06-17", proposedMin: 8*60, currentLoggedMin: 179),
        ]
        var s = Calculator.makeSnapshot(
            config: config,
            hubChrono: TimesheetParser.parseHubChrono(hub),
            monthBalanceMin: TimesheetParser.parseMonthBalance(logs),
            monthLoggedMin: TimesheetParser.parseMonthLogged(logs),
            days: TimesheetParser.parseDays(logs),
            pending: pending,
            now: cal.date(from: DateComponents(year: 2026, month: 6, day: 18, hour: 12))!)
        s.year = PeriodStat(label: "This year", officialBalanceMin: 14*60 + 30)   // made up: needs past months
        s.generatedAt = now
        s.chrono = TimesheetParser.parseChronoState(chronoHTML)
        // Started 2.5 h ago, so "since" comes before "Leave by".
        if s.chrono?.status != .stopped { s.chrono?.startedAt = stamp(now.addingTimeInterval(-9000)) }

        switch state {
        case "not-checked-in":
            s.today.loggedMin = 0
            s.today.officialBalanceMin = -s.today.expectedMin
        case "done":
            s.today.loggedMin = s.today.expectedMin + 5
            s.today.officialBalanceMin = 5
        case "off":
            s.today = PeriodStat(label: s.today.label)
        case "unknown":
            s.chrono?.status = .unknown
        default:
            break   // working, break, checked-out: the fixtures as they are
        }
        return s
    }

    /// A clock action, applied in memory only.
    static func perform(_ action: ChronoAction, on snap: Snapshot, now: Date = Date()) -> Snapshot {
        var s = snap
        switch action {
        case .checkIn, .resume: s.chrono?.status = .working
        case .takeBreak: s.chrono?.status = .paused
        case .checkOut: s.chrono?.status = .stopped
        }
        if action != .checkOut { s.chrono?.startedAt = stamp(now) }
        return s
    }

    /// Bizneo's `data-from` format, e.g. "2026-6-22 15:10:07", in Madrid time.
    private static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Madrid")
        f.dateFormat = "yyyy-M-d HH:mm:ss"
        return f.string(from: date)
    }
}
