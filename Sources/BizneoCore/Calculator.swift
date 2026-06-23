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

        return Snapshot(today: today, week: week, month: month,
                        pending: pending.filter { monthDays.contains($0.dateString) || includePending },
                        monthLoggedMin: monthLoggedMin, generatedAt: now)
    }
}
