import Foundation

/// Combines parsed data into today/week/month figures (official + projected-with-pending).
public enum Calculator {

    /// Europe/Madrid calendar (Bizneo's timezone for this tenant).
    public static func madridCalendar(weekStartsMonday: Bool) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Madrid") ?? .current
        cal.firstWeekday = weekStartsMonday ? 2 : 1
        return cal
    }

    static func ymd(_ date: Date, _ cal: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Inclusive list of `yyyy-MM-dd` strings from `start` to `end`.
    static func dayStrings(from start: Date, to end: Date, _ cal: Calendar) -> Set<String> {
        var out = Set<String>()
        var d = cal.startOfDay(for: start)
        let last = cal.startOfDay(for: end)
        while d <= last {
            out.insert(ymd(d, cal))
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return out
    }

    /// Sum of daily balances over `days`, with day-off ("Fridom") days corrected
    /// to expected = 0 (their deficit added back). Used for the year-to-date total.
    public static func dayOffCorrectedSum(days: [DayLog], dayOffNames: [String]) -> Int {
        days.reduce(0) { acc, d in
            acc + (d.balanceMin ?? 0) + d.dayOffCorrection(dayOffNames)
        }
    }

    /// Merge pending change-requests from several months into one display list.
    ///
    /// Deduplicates by request id — **earlier lists win**, so callers pass the
    /// freshest (current-month) list first and a stale cached copy can never
    /// shadow it. Sorted by date because the caller's source is a dictionary's
    /// `.values`, which has no defined order.
    public static func mergePending(_ lists: [[PendingRequest]]) -> [PendingRequest] {
        var seen = Set<String>()
        var out: [PendingRequest] = []
        for list in lists {
            for r in list where seen.insert(r.id).inserted { out.append(r) }
        }
        return out.sorted { $0.dateString < $1.dateString }
    }

    /// Wall-clock time at which today's target is reached, assuming you keep
    /// working without further breaks. `nil` when already at/over target (i.e.
    /// the projected balance is non-negative). Uses the projected balance so the
    /// result is consistent with the "missing" figure shown on the Today row.
    public static func expectedCheckout(today: PeriodStat, generatedAt: Date) -> Date? {
        let owedMin = -today.projectedBalanceMin
        guard owedMin > 0 else { return nil }
        return generatedAt.addingTimeInterval(Double(owedMin) * 60)
    }

    /// Build a snapshot. `now` is injectable for testing.
    public static func makeSnapshot(config: Config,
                                    hubChrono: (scheduledMin: Int, loggedMin: Int)?,
                                    monthBalanceMin: Int?,
                                    monthLoggedMin: Int?,
                                    days: [DayLog],
                                    pending: [PendingRequest],
                                    now: Date = Date()) -> Snapshot {
        let cal = madridCalendar(weekStartsMonday: config.weekStartsMonday)
        let todayStr = ymd(now, cal)

        // Day range sets for week-to-date and month-to-date.
        let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let monthStart = cal.dateInterval(of: .month, for: now)?.start ?? now
        let weekDays = dayStrings(from: weekStart, to: now, cal)
        let monthDays = dayStrings(from: monthStart, to: now, cal)

        let includePending = config.includePending
        let pendingByDate = Dictionary(grouping: pending, by: { $0.dateString })
        let dayOffNames = config.dayOffScheduleNames

        func pendingDelta(in dateSet: Set<String>) -> Int {
            guard includePending else { return 0 }
            var sum = 0
            for (date, reqs) in pendingByDate where dateSet.contains(date) {
                for r in reqs { sum += r.deltaMin }
            }
            return sum
        }

        // On a company day off (e.g. "Fridom") the schedule still expects hours, so
        // On a company day off (e.g. "Fridom") the schedule still expects hours, so
        // Bizneo shows a negative balance. We treat expected as 0, i.e. add the
        // expected minutes back so the day no longer counts as "missing". Only when
        // the day actually carries a balance (see DayLog.dayOffCorrection).
        func dayOffCorrection(_ d: DayLog) -> Int {
            d.dayOffCorrection(dayOffNames)
        }

        // ----- Today (prefer live hub_chrono; fall back to my-logs day row) -----
        var today = PeriodStat(label: "Today")
        let todayRow = days.first(where: { $0.dateString == todayStr })
        let todayIsDayOff = todayRow?.isDayOff(dayOffNames) ?? false
        if let hc = hubChrono {
            today.expectedMin = todayIsDayOff ? 0 : hc.scheduledMin
            today.loggedMin = hc.loggedMin
            today.officialBalanceMin = hc.loggedMin - today.expectedMin
        } else if let row = todayRow {
            today.expectedMin = todayIsDayOff ? 0 : (row.expectedMin ?? 0)
            today.loggedMin = row.loggedMin ?? 0
            today.officialBalanceMin = (row.balanceMin ?? 0) + (todayIsDayOff ? (row.expectedMin ?? 0) : 0)
        }
        today.pendingDeltaMin = pendingDelta(in: [todayStr])

        // ----- Week-to-date (sum of daily balances, day-off-corrected) -----
        var week = PeriodStat(label: "This week")
        for d in days where weekDays.contains(d.dateString) {
            week.officialBalanceMin += (d.balanceMin ?? 0) + dayOffCorrection(d)
            week.loggedMin += d.loggedMin ?? 0
            week.expectedMin += d.isDayOff(dayOffNames) ? 0 : (d.expectedMin ?? 0)
        }
        week.pendingDeltaMin = pendingDelta(in: weekDays)

        // ----- Month-to-date (authoritative header balance, day-off-corrected) -----
        var month = PeriodStat(label: "This month")
        if let mb = monthBalanceMin {
            // Header "Until today" bakes in past day-off deficits → add them back.
            let correction = days
                .filter { monthDays.contains($0.dateString) }
                .reduce(0) { $0 + dayOffCorrection($1) }
            month.officialBalanceMin = mb + correction
        } else {
            for d in days where monthDays.contains(d.dateString) {
                month.officialBalanceMin += (d.balanceMin ?? 0) + dayOffCorrection(d)
            }
        }
        month.loggedMin = monthLoggedMin ?? days.filter { monthDays.contains($0.dateString) }
            .reduce(0) { $0 + ($1.loggedMin ?? 0) }
        month.pendingDeltaMin = pendingDelta(in: monthDays)

        // ----- Reconcile -----
        // week/month/year come from the timesheet, which only counts *committed*
        // time, while `today` (hub_chrono) includes the currently-running session.
        // Fold that delta into the longer periods so they don't lag the timer.
        // (year inherits this via computeYear, which is built from snapshot.month.)
        if hubChrono != nil {
            let committedToday = (todayRow?.balanceMin ?? 0) + (todayRow?.dayOffCorrection(dayOffNames) ?? 0)
            let liveDelta = today.officialBalanceMin - committedToday
            week.officialBalanceMin += liveDelta
            month.officialBalanceMin += liveDelta
        }

        return Snapshot(today: today, week: week, month: month,
                        pending: pending.filter { monthDays.contains($0.dateString) || includePending },
                        monthLoggedMin: monthLoggedMin, generatedAt: now)
    }
}
