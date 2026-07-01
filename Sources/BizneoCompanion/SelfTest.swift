import Foundation
import BizneoCore

/// Lightweight test runner (XCTest is unavailable with Command Line Tools only).
/// Validates the parsers against the captured HTML fixtures.
/// Usage: `BizneoCompanion --selftest [fixturesDir]`
enum SelfTest {
    static var failures = 0

    static func check(_ cond: Bool, _ msg: String, _ got: Any? = nil) {
        if cond { print("  ✓ \(msg)") }
        else { failures += 1; print("  ✗ \(msg)  (got: \(got.map { "\($0)" } ?? "nil"))") }
    }

    static func run(dir: String) -> Int {
        let base = URL(fileURLWithPath: dir)
        func load(_ name: String) -> String {
            (try? String(contentsOf: base.appendingPathComponent(name), encoding: .utf8)) ?? ""
        }
        let hub = load("hub_chrono.html")
        let logs = load("my_logs.html")
        guard !hub.isEmpty, !logs.isEmpty else {
            print("FIXTURES NOT FOUND in \(dir) (need hub_chrono.html, my_logs.html)")
            return 2
        }

        print("TimeFmt:")
        check(TimeFmt.parseHM("8:00") == 480, "parse 8:00 == 480", TimeFmt.parseHM("8:00") as Any)
        check(TimeFmt.parseHM("-2:43") == -163, "parse -2:43 == -163")
        check(TimeFmt.parseHhMm("-14h 21m") == -861, "parse -14h 21m == -861")
        check(TimeFmt.signed(-163) == "-2:43", "format -163 == -2:43")
        check(TimeFmt.signedHMS(-26790) == "-7:26:30", "signedHMS -26790 == -7:26:30", TimeFmt.signedHMS(-26790))
        check(TimeFmt.signedHMS(90) == "+0:01:30", "signedHMS 90 == +0:01:30")
        check(TimeFmt.signedHMS(0) == "+0:00:00", "signedHMS 0 == +0:00:00")

        print("liveSeconds (live tick):")
        let lp = PeriodStat(label: "x", officialBalanceMin: -2, pendingDeltaMin: 0)  // projected -2 min
        check(lp.liveSeconds(working: false, elapsedSinceRefresh: 100) == -120, "not working → -2:00 static", lp.liveSeconds(working: false, elapsedSinceRefresh: 100))
        check(lp.liveSeconds(working: true, elapsedSinceRefresh: 45) == -75, "working → -120 + 45s", lp.liveSeconds(working: true, elapsedSinceRefresh: 45))
        check(lp.liveSeconds(working: true, elapsedSinceRefresh: -5) == -120, "working + clock skew clamps to 0", lp.liveSeconds(working: true, elapsedSinceRefresh: -5))

        print("hub_chrono (today):")
        let hc = TimesheetParser.parseHubChrono(hub)
        check(hc?.scheduledMin == 480, "scheduled == 8:00", hc?.scheduledMin as Any)
        check(hc?.loggedMin == 451, "logged == 7:31", hc?.loggedMin as Any)

        print("my-logs header (month):")
        check(TimesheetParser.parseMonthBalance(logs) == -861, "month balance == -14h21m",
              TimesheetParser.parseMonthBalance(logs) as Any)
        check(TimesheetParser.parseMonthLogged(logs) == 93*60+39, "month logged == 93h39m",
              TimesheetParser.parseMonthLogged(logs) as Any)

        print("my-logs day rows:")
        let days = TimesheetParser.parseDays(logs)
        let byDate = Dictionary(days.map { ($0.dateString, $0) }, uniquingKeysWith: { a, _ in a })
        check(byDate["2026-06-15"]?.balanceMin == -125, "Mon15 balance -2:05", byDate["2026-06-15"]?.balanceMin as Any)
        check(byDate["2026-06-15"]?.expectedMin == 480, "Mon15 expected 8:00", byDate["2026-06-15"]?.expectedMin as Any)
        check(byDate["2026-06-15"]?.loggedMin == 355, "Mon15 logged 5:55", byDate["2026-06-15"]?.loggedMin as Any)
        check(byDate["2026-06-15"]?.pendingRequestId == "1275258", "Mon15 pending 1275258", byDate["2026-06-15"]?.pendingRequestId as Any)
        check(byDate["2026-06-17"]?.pendingRequestId == "1283627", "Wed17 pending 1283627", byDate["2026-06-17"]?.pendingRequestId as Any)
        check(byDate["2026-06-16"]?.pendingRequestId == nil, "Tue16 NOT pending", byDate["2026-06-16"]?.pendingRequestId as Any)
        check(byDate["2026-06-18"]?.balanceMin == -163, "Thu18 balance -2:43", byDate["2026-06-18"]?.balanceMin as Any)
        let pendingIds = Set(days.compactMap { $0.pendingRequestId })
        check(pendingIds == ["1275258", "1283627"], "exactly two pending requests", pendingIds)

        print("Fridom (company day off):")
        check(byDate["2026-06-05"]?.scheduleName == "Fridom", "Jun5 schedule == Fridom", byDate["2026-06-05"]?.scheduleName as Any)
        check(byDate["2026-06-12"]?.scheduleName == "Friday", "Jun12 schedule == Friday", byDate["2026-06-12"]?.scheduleName as Any)
        check(byDate["2026-06-05"]?.isDayOff(["Fridom"]) == true, "Jun5 is a day off", byDate["2026-06-05"]?.isDayOff(["Fridom"]) as Any)
        check(byDate["2026-06-12"]?.isDayOff(["Fridom"]) == false, "Jun12 is NOT a day off")
        check(byDate["2026-06-05"]?.balanceMin == -360, "Jun5 raw balance -6:00", byDate["2026-06-05"]?.balanceMin as Any)

        // Day-off correction must only cancel a real deficit, never credit a 0/neutral day.
        let fridomDeficit = DayLog(dateString: "x", scheduleName: "Fridom", expectedMin: 360, balanceMin: -360)
        let fridomNoBalance = DayLog(dateString: "x", scheduleName: "Fridom", expectedMin: 360, balanceMin: nil)
        let fridomWorked = DayLog(dateString: "x", scheduleName: "Fridom", expectedMin: 360, balanceMin: 60)
        check(fridomDeficit.dayOffCorrection(["Fridom"]) == 360, "Fridom deficit → +6:00 correction", fridomDeficit.dayOffCorrection(["Fridom"]))
        check(fridomNoBalance.dayOffCorrection(["Fridom"]) == 0, "Fridom w/o balance → no credit (bug fix)", fridomNoBalance.dayOffCorrection(["Fridom"]))
        check(fridomWorked.dayOffCorrection(["Fridom"]) == 360, "Fridom worked (+balance) → still +6:00", fridomWorked.dayOffCorrection(["Fridom"]))
        // dayOffCorrectedSum: deficit cancels to 0, no-balance contributes 0 (not +6:00).
        check(Calculator.dayOffCorrectedSum(days: [fridomDeficit, fridomNoBalance], dayOffNames: ["Fridom"]) == 0,
              "sum: deficit+no-balance Fridoms == 0", Calculator.dayOffCorrectedSum(days: [fridomDeficit, fridomNoBalance], dayOffNames: ["Fridom"]))

        print("calculator (projected, now=Thu 18 Jun 2026):")
        var cfg = Config(); cfg.includePending = true
        let pending = [
            PendingRequest(id: "1275258", dateString: "2026-06-15", proposedMin: 8*60+14, currentLoggedMin: 355),
            PendingRequest(id: "1283627", dateString: "2026-06-17", proposedMin: 8*60, currentLoggedMin: 179),
        ]
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Madrid")!
        let now = c.date(from: DateComponents(year: 2026, month: 6, day: 18, hour: 12))!
        let snap = Calculator.makeSnapshot(config: cfg, hubChrono: hc, monthBalanceMin: TimesheetParser.parseMonthBalance(logs),
                                           monthLoggedMin: nil, days: days, pending: pending, now: now)
        // Month official -14:21 from header, corrected for Jun5 "Fridom" day off (+6:00) → -8:21.
        // Reconcile folds the live "today" delta (hub -0:29 vs my-logs -2:43 = +2:14 = 134)
        // into week/month/year.
        check(snap.month.officialBalanceMin == -861 + 360 + 134, "month official (Fridom + reconcile)", snap.month.officialBalanceMin)
        check(snap.month.pendingDeltaMin == 139+301, "month pending delta +7:20", snap.month.pendingDeltaMin)
        check(snap.month.projectedBalanceMin == -861 + 360 + 134 + 440, "month projected", snap.month.projectedBalanceMin)
        check(snap.today.officialBalanceMin == 451-480, "today official -0:29", snap.today.officialBalanceMin)
        check(snap.today.pendingDeltaMin == 0, "today no pending", snap.today.pendingDeltaMin)

        print("checkout time (expected leave):")
        // Today is 0:29 behind (projected) and now=12:00 → leave by 12:29.
        let checkout = Calculator.expectedCheckout(today: snap.today, generatedAt: snap.generatedAt)
        check(checkout == now.addingTimeInterval(29*60), "checkout == now + 0:29", checkout as Any)
        let madrid = Calculator.madridCalendar(weekStartsMonday: true)
        check(checkout.map { TimeFmt.clock($0, calendar: madrid) } == "12:29", "checkout clock == 12:29",
              checkout.map { TimeFmt.clock($0, calendar: madrid) } as Any)
        // Non-negative (at/over target) → no checkout time.
        var aheadToday = PeriodStat(label: "Today"); aheadToday.officialBalanceMin = 15
        check(Calculator.expectedCheckout(today: aheadToday, generatedAt: now) == nil, "ahead → no checkout time")
        let sixTwentyEight = c.date(from: DateComponents(year: 2026, month: 6, day: 18, hour: 16, minute: 28))!
        check(TimeFmt.clock(sixTwentyEight, calendar: madrid) == "16:28", "clock formats 16:28",
              TimeFmt.clock(sixTwentyEight, calendar: madrid))
        let weekRaw = -125 + -5 + -301 + -163   // Mon15..Thu18 committed balances
        check(snap.week.officialBalanceMin == weekRaw + 134, "week official (sum + reconcile)", snap.week.officialBalanceMin)
        check(snap.week.officialBalanceMin - weekRaw == 134, "reconcile +2:14 folded into week", snap.week.officialBalanceMin - weekRaw)

        print("chrono state parsing:")
        let working = TimesheetParser.parseChronoState(load("chrono_working.html"))
        check(working.status == .working, "working status", working.status)
        check(working.chronoId == "26919", "working chronoId 26919", working.chronoId as Any)
        check(working.shiftId == "17724806", "working shiftId", working.shiftId as Any)
        check(working.csrfToken?.isEmpty == false, "working has csrf token")
        check(working.startedAt == "2026-6-22 15:10:07", "working startedAt", working.startedAt as Any)
        check(working.projects.count == 8, "working 8 projects", working.projects.count)
        check(working.projects.first(where: { $0.id == "15741264" })?.name == "Project D", "project name decoded",
              working.projects.first(where: { $0.id == "15741264" })?.name as Any)

        let paused = TimesheetParser.parseChronoState(load("chrono_paused.html"))
        check(paused.status == .paused, "paused status", paused.status)
        check(paused.chronoId == "26919", "paused chronoId", paused.chronoId as Any)

        let stopped = TimesheetParser.parseChronoState(load("chrono_stopped.html"))
        check(stopped.status == .stopped, "stopped status", stopped.status)
        check(stopped.chronoId == nil, "stopped has no chronoId", stopped.chronoId as Any)
        check(stopped.shiftId == "17724806", "stopped shiftId", stopped.shiftId as Any)
        check(stopped.projects.count == 8, "stopped 8 projects", stopped.projects.count)

        print("year aggregation + bar metric:")
        // day-off corrected sum of the June fixture (used as a synthetic "past month").
        let monthSum = Calculator.dayOffCorrectedSum(days: days, dayOffNames: ["Fridom"])
        // Synthesize a snapshot with a year = pastMonth(monthSum) + current month official.
        var sy = snap
        var yr = PeriodStat(label: "This year")
        yr.officialBalanceMin = monthSum + snap.month.officialBalanceMin
        yr.pendingDeltaMin = snap.month.pendingDeltaMin
        sy.year = yr
        check(sy.stat(for: .year).officialBalanceMin == monthSum + snap.month.officialBalanceMin,
              "year = pastSum + current month", sy.stat(for: .year).officialBalanceMin)
        check(sy.stat(for: .week).projectedBalanceMin == snap.week.projectedBalanceMin,
              "barMetric .week selects week", sy.stat(for: .week).projectedBalanceMin)
        check(sy.stat(for: .today).projectedBalanceMin == snap.today.projectedBalanceMin,
              "barMetric .today selects today")
        check(sy.stat(for: .year).label == "This year", "barMetric .year selects year")

        print("config defaults:")
        let dc = Config()
        check(dc.barMetric == .week, "default barMetric == week", dc.barMetric.rawValue)
        check(dc.defaultTelework == true, "default telework == true")
        check(dc.enableYearTotal == true, "default enableYearTotal == true")
        check(dc.dropdownSecondsScope == .today, "default dropdownSecondsScope == today", dc.dropdownSecondsScope.rawValue)

        print(failures == 0 ? "\nALL PASSED ✅" : "\n\(failures) FAILED ❌")
        return failures == 0 ? 0 : 1
    }
}
