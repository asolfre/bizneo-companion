import Foundation

/// Check-in reminder logic (#16). Pure: no I/O and no clock reads. The app passes
/// in the time, the calendar and what it last observed, so `--selftest` can drive
/// every branch. See `docs/plans/done/check-in-reminders.md`.
public enum Reminders {

    /// `"08:00-10:00"` → `480..<600`, minutes since midnight. The start is inside the
    /// window, the end isn't. `nil` for signs, times outside 00:00–23:59, empty
    /// windows and windows crossing midnight (nothing in this app runs overnight).
    public static func parseWindow(_ s: String) -> Range<Int>? {
        let parts = s.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let start = clockMinute(String(parts[0])),
              let end = clockMinute(String(parts[1])),
              start < end else { return nil }
        return start..<end
    }

    /// `TimeFmt.parseHM` accepts signs, durations past 24h and `:75`; a wall-clock
    /// time can't have any of them.
    private static func clockMinute(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.hasPrefix("+"), let m = TimeFmt.parseHM(t),
              let mm = Int(t.suffix(2)), mm < 60, m < 24 * 60 else { return nil }
        return m
    }

    /// The usable windows from `Config.reminderWindows`. Invalid entries are dropped:
    /// `config.json` can be hand-edited, and one typo shouldn't disable the rest.
    public static func windows(_ list: [String]) -> [Range<Int>] {
        list.compactMap(parseWindow)
    }

    /// The states a reminder is about: never started, left early, still on a break.
    public static func isRemindable(_ s: BarState) -> Bool {
        s == .notCheckedIn || s == .checkedOutEarly || s == .onBreak
    }

    public static func minuteOfDay(_ d: Date, calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// `"2026-10-06"` in `calendar`'s timezone: the key "Not today" is stored under.
    public static func dayKey(_ d: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public struct Context {
        public var now: Date
        /// Europe/Madrid in the app (`Calculator.madridCalendar`), the same day
        /// boundary Bizneo's "today" uses.
        public var calendar: Calendar
        public var windows: [Range<Int>]
        public var intervalMinutes: Int
        /// Display awake, session unlocked, and this user at the console.
        public var screenActive: Bool
        /// `dayKey` of the last "Not today", if any.
        public var snoozedDay: String?
        /// Clock state from the last *successful* refresh; nil before the first.
        public var state: BarState?
        /// The most recent refresh attempt failed.
        public var refreshFailed: Bool
        /// When the last refresh attempt finished, successful or not. Staleness is
        /// measured from attempts, not successes, or a failing Bizneo would be
        /// retried on every tick.
        public var lastAttemptAt: Date?
        public var lastRemindedAt: Date?
        public var lastFailureNoticeAt: Date?

        public init(now: Date, calendar: Calendar, windows: [Range<Int>], intervalMinutes: Int,
                    screenActive: Bool, snoozedDay: String? = nil, state: BarState?,
                    refreshFailed: Bool = false, lastAttemptAt: Date?,
                    lastRemindedAt: Date? = nil, lastFailureNoticeAt: Date? = nil) {
            self.now = now; self.calendar = calendar; self.windows = windows
            self.intervalMinutes = intervalMinutes; self.screenActive = screenActive
            self.snoozedDay = snoozedDay; self.state = state; self.refreshFailed = refreshFailed
            self.lastAttemptAt = lastAttemptAt; self.lastRemindedAt = lastRemindedAt
            self.lastFailureNoticeAt = lastFailureNoticeAt
        }
    }

    public enum Step: Equatable {
        /// Nothing to remind about: outside every window, screen inactive, "Not
        /// today", or a state that doesn't need it. Withdraw delivered reminders, so
        /// a stale "Check in" can't be pressed later.
        case idle
        /// Refresh, then ask again with `justRefreshed: true`. Used both when the data
        /// is older than the interval and to confirm before every reminder, so a
        /// check-in made on the web or the phone never gets a false reminder.
        case refresh
        case remind
        /// Inside a window, Bizneo can't be read (expired session, no network).
        case failureNotice
        /// Something is pending, just not yet: interval not elapsed, or the failure
        /// already noticed in this window. Leave delivered notifications alone.
        case wait
    }

    public static func next(_ c: Context, justRefreshed: Bool) -> Step {
        let minute = minuteOfDay(c.now, calendar: c.calendar)
        let today = dayKey(c.now, calendar: c.calendar)
        guard c.screenActive, c.snoozedDay != today,
              let window = c.windows.first(where: { $0.contains(minute) })
        else { return .idle }

        let interval = TimeInterval(max(1, c.intervalMinutes) * 60)
        let stale = c.lastAttemptAt.map { c.now.timeIntervalSince($0) >= interval } ?? true
        let refreshOr: (Step) -> Step = { (!justRefreshed && stale) ? .refresh : $0 }

        if c.refreshFailed {
            let noticed = c.lastFailureNoticeAt.map {
                dayKey($0, calendar: c.calendar) == today
                    && window.contains(minuteOfDay($0, calendar: c.calendar))
            } ?? false
            // Retry once ourselves before telling anyone: a refresh right after wake
            // often fails on the network alone.
            if !noticed { return justRefreshed ? .failureNotice : .refresh }
            return refreshOr(.wait)
        }

        guard let state = c.state, isRemindable(state) else { return refreshOr(.idle) }
        let due = c.lastRemindedAt.map { c.now.timeIntervalSince($0) >= interval } ?? true
        guard due else { return refreshOr(.wait) }
        return justRefreshed ? .remind : .refresh
    }
}
