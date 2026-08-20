import XCTest
@testable import BizneoCore

final class ParserTests: XCTestCase {

    func fixture(_ name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: name, withExtension: "html") else {
            throw XCTSkip("fixture \(name).html not found")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: TimeFmt

    func testTimeParsing() {
        XCTAssertEqual(TimeFmt.parseHM("8:00"), 480)
        XCTAssertEqual(TimeFmt.parseHM("-2:43"), -163)
        XCTAssertEqual(TimeFmt.parseHM("+0:14"), 14)
        XCTAssertEqual(TimeFmt.parseHhMm("93h 39m"), 93 * 60 + 39)
        XCTAssertEqual(TimeFmt.parseHhMm("-14h 21m"), -(14 * 60 + 21))
        XCTAssertEqual(TimeFmt.rangeMinutes("09:48", "18:48"), 540)
        XCTAssertEqual(TimeFmt.signed(-163), "-2:43")
        XCTAssertEqual(TimeFmt.signed(14), "+0:14")
    }

    // MARK: hub_chrono (today)

    func testHubChrono() throws {
        let html = try fixture("hub_chrono")
        let r = TimesheetParser.parseHubChrono(html)
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.scheduledMin, 480)        // 8:00
        XCTAssertEqual(r?.loggedMin, 7 * 60 + 31)   // 7:31
    }

    // MARK: my-logs header (month)

    func testMonthBalance() throws {
        let html = try fixture("my_logs")
        let bal = TimesheetParser.parseMonthBalance(html)
        XCTAssertEqual(bal, -(14 * 60 + 21))        // -14h 21m "Until today"
    }

    func testMonthLogged() throws {
        let html = try fixture("my_logs")
        let logged = TimesheetParser.parseMonthLogged(html)
        XCTAssertEqual(logged, 93 * 60 + 39)        // 93h 39m
    }

    // MARK: day rows + pending detection

    func testParseDays() throws {
        let html = try fixture("my_logs")
        let days = TimesheetParser.parseDays(html)
        let byDate = Dictionary(uniqueKeysWithValues: days.map { ($0.dateString, $0) })

        // Mon 15: expected 8:00, logged 5:55, balance -2:05, pending request 1275258.
        let mon = try XCTUnwrap(byDate["2026-06-15"])
        XCTAssertEqual(mon.expectedMin, 480)
        XCTAssertEqual(mon.balanceMin, -(2 * 60 + 5))
        XCTAssertEqual(mon.loggedMin, 5 * 60 + 55)
        XCTAssertEqual(mon.pendingRequestId, "1275258")
        XCTAssertEqual(mon.scheduleName, "Mon-Thu")

        // Jun 5 "Fridom" = company day off; Jun 12 "Friday" = normal.
        XCTAssertEqual(byDate["2026-06-05"]?.scheduleName, "Fridom")
        XCTAssertTrue(byDate["2026-06-05"]?.isDayOff(["Fridom"]) ?? false)
        XCTAssertFalse(byDate["2026-06-12"]?.isDayOff(["Fridom"]) ?? true)

        // Wed 17: pending request 1283627, balance -5:01.
        let wed = try XCTUnwrap(byDate["2026-06-17"])
        XCTAssertEqual(wed.pendingRequestId, "1283627")
        XCTAssertEqual(wed.balanceMin, -(5 * 60 + 1))

        // Tue 16: "Request change" CTA only → NOT pending.
        let tue = try XCTUnwrap(byDate["2026-06-16"])
        XCTAssertNil(tue.pendingRequestId)
        XCTAssertEqual(tue.balanceMin, -5)          // -0:05

        // Today (Thu 18): no pending, balance -2:43.
        let thu = try XCTUnwrap(byDate["2026-06-18"])
        XCTAssertNil(thu.pendingRequestId)
        XCTAssertEqual(thu.balanceMin, -(2 * 60 + 43))
    }

    func testExactlyTwoPending() throws {
        let html = try fixture("my_logs")
        let days = TimesheetParser.parseDays(html)
        let pendingIds = Set(days.compactMap { $0.pendingRequestId })
        XCTAssertEqual(pendingIds, ["1275258", "1283627"])
    }

    // MARK: calculator end-to-end (with a synthetic pending duration)

    func testCalculatorProjected() throws {
        let html = try fixture("my_logs")
        let days = TimesheetParser.parseDays(html)
        let hub = TimesheetParser.parseHubChrono(try fixture("hub_chrono"))
        let monthBal = TimesheetParser.parseMonthBalance(html)

        // Simulate fetched request details: Mon15 proposes 8:14, Wed17 proposes 8:00.
        let pending = [
            PendingRequest(id: "1275258", dateString: "2026-06-15", proposedMin: 8 * 60 + 14,
                           currentLoggedMin: 5 * 60 + 55),
            PendingRequest(id: "1283627", dateString: "2026-06-17", proposedMin: 8 * 60,
                           currentLoggedMin: 2 * 60 + 59),
        ]

        var cfg = Config()
        cfg.includePending = true
        // Pin "now" to Thu 18 Jun 2026 12:00 Madrid.
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Madrid")!
        let now = c.date(from: DateComponents(year: 2026, month: 6, day: 18, hour: 12))!

        let snap = Calculator.makeSnapshot(config: cfg, hubChrono: hub, monthBalanceMin: monthBal,
                                           monthLoggedMin: nil, days: days, pending: pending, now: now)

        // Reconcile: week/month fold in the live "today" delta (hub_chrono includes
        // the running session) vs the committed my-logs Thu18 row.
        // = (7:31-8:00) - (-2:43) = -0:29 + 2:43 = +2:14 = 134 min.
        let reconcile = ((7 * 60 + 31) - 480) - -(2 * 60 + 43)

        // Month official = -14:21 (header) + 6:00 (Jun5 Fridom correction) + reconcile.
        XCTAssertEqual(snap.month.officialBalanceMin, -(14 * 60 + 21) + 360 + reconcile)
        // Pending delta = (8:14-5:55) + (8:00-2:59) = 2:19 + 5:01 = 7:20 = 440 min.
        XCTAssertEqual(snap.month.pendingDeltaMin, (2 * 60 + 19) + (5 * 60 + 1))
        // Projected month = -861 + 360 + reconcile + 440.
        XCTAssertEqual(snap.month.projectedBalanceMin, -(14 * 60 + 21) + 360 + reconcile + ((2 * 60 + 19) + (5 * 60 + 1)))

        // Week (Mon15..Thu18) official = sum of daily balances + reconcile.
        let expectedWeek = -(2*60+5) + -(5) + -(5*60+1) + -(2*60+43)
        XCTAssertEqual(snap.week.officialBalanceMin, expectedWeek + reconcile)
        XCTAssertEqual(snap.week.pendingDeltaMin, (2*60+19) + (5*60+1))

        // Today from hub_chrono: 7:31 - 8:00 = -29 min, no pending.
        XCTAssertEqual(snap.today.officialBalanceMin, (7*60+31) - 480)
        XCTAssertEqual(snap.today.pendingDeltaMin, 0)

        // Expected checkout: 0:29 behind (projected) at 12:00 → leave by 12:29.
        let checkout = Calculator.expectedCheckout(today: snap.today, generatedAt: snap.generatedAt)
        XCTAssertEqual(checkout, now.addingTimeInterval(29 * 60))
        let madrid = Calculator.madridCalendar(weekStartsMonday: true)
        XCTAssertEqual(checkout.map { TimeFmt.clock($0, calendar: madrid) }, "12:29")
        XCTAssertEqual(TimeFmt.clock(
            c.date(from: DateComponents(year: 2026, month: 6, day: 18, hour: 16, minute: 28))!,
            calendar: madrid), "16:28")
        // At/over target → no checkout time.
        XCTAssertNil(Calculator.expectedCheckout(
            today: PeriodStat(label: "Today", officialBalanceMin: 15), generatedAt: now))
    }

    // MARK: menu-bar clock state

    /// Bizneo reports "never checked in" and "checked out" as the same `.stopped`
    /// status, so the three stopped sub-states are inferred from today's figures.
    func testBarState() throws {
        let working = TimesheetParser.parseChronoState(try fixture("chrono_working")).status
        let paused = TimesheetParser.parseChronoState(try fixture("chrono_paused")).status
        let stopped = TimesheetParser.parseChronoState(try fixture("chrono_stopped")).status

        let freshDay = PeriodStat(label: "Today", loggedMin: 0, expectedMin: 480, officialBalanceMin: -480)
        XCTAssertEqual(BarState.derive(chrono: working, today: freshDay), .working)
        XCTAssertEqual(BarState.derive(chrono: paused, today: freshDay), .onBreak)

        // The state this feature exists for.
        XCTAssertEqual(BarState.derive(chrono: stopped, today: freshDay), .notCheckedIn)
        XCTAssertTrue(BarState.derive(chrono: stopped, today: freshDay).needsAttention)

        // Deliberate early stop: same deficit, but not a "you forgot" warning.
        let short = PeriodStat(label: "Today", loggedMin: 400, expectedMin: 480, officialBalanceMin: -80)
        XCTAssertEqual(BarState.derive(chrono: stopped, today: short), .checkedOutEarly)
        XCTAssertFalse(BarState.derive(chrono: stopped, today: short).needsAttention)

        let complete = PeriodStat(label: "Today", loggedMin: 480, expectedMin: 480, officialBalanceMin: 0)
        XCTAssertEqual(BarState.derive(chrono: stopped, today: complete), .doneForToday)

        // Pending (unapproved) changes count towards the target, matching the
        // "missing" figure on the Today row.
        let viaPending = PeriodStat(label: "Today", loggedMin: 0, expectedMin: 480,
                                    officialBalanceMin: -480, pendingDeltaMin: 480)
        XCTAssertEqual(BarState.derive(chrono: stopped, today: viaPending), .doneForToday)

        // Weekend / holiday / company day off — Calculator zeroes expected minutes.
        let dayOff = PeriodStat(label: "Today", loggedMin: 0, expectedMin: 0, officialBalanceMin: 0)
        XCTAssertEqual(BarState.derive(chrono: stopped, today: dayOff), .offDuty)

        XCTAssertEqual(BarState.derive(chrono: .unknown, today: freshDay), .unknown)
        XCTAssertEqual(BarState.derive(chrono: nil, today: freshDay), .unknown)
    }

    /// A healthy weekly total (what the bar shows by default) must not mask a
    /// forgotten check-in today.
    func testBarStateIgnoresBarMetric() throws {
        let stopped = TimesheetParser.parseChronoState(try fixture("chrono_stopped"))
        var snap = Snapshot(today: PeriodStat(label: "Today", loggedMin: 0, expectedMin: 480,
                                              officialBalanceMin: -480),
                            week: PeriodStat(label: "This week", officialBalanceMin: 120),
                            month: PeriodStat(label: "This month", officialBalanceMin: 300),
                            pending: [], monthLoggedMin: nil, generatedAt: Date())
        snap.chrono = stopped
        XCTAssertGreaterThan(snap.stat(for: .week).projectedBalanceMin, 0)
        XCTAssertEqual(snap.barState, .notCheckedIn)
    }
}
