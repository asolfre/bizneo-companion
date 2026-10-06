import Foundation

/// Which period the menu-bar number reflects.
public enum BarMetric: String, Codable, CaseIterable {
    case today, week, month, year
}

/// Which dropdown rows show live seconds (`H:MM:SS`) while the timer runs.
/// `none` = never; `today` = Today row only (default); `all` = every period row.
public enum DropdownSecondsScope: String, Codable, CaseIterable {
    case none, today, all
}

/// Which backlog the "Leave by" time clears.
///
/// `none` (default) = today's target only, i.e. leave when today's own balance
/// reaches zero. The others fold in the whole period's deficit, so "Leave by"
/// answers "when have I cleared the week/month/year?" instead.
///
/// This deliberately does **not** touch the menu-bar number: that is `barMetric`'s
/// job, and a scope applied there would render exactly what `barMetric` already
/// renders. See `docs/plans/done/leave-by-scope.md`.
public enum LeaveByScope: String, Codable, CaseIterable {
    case none, week, month, year
}

/// User-editable configuration, persisted to
/// `~/Library/Application Support/BizneoCompanion/config.json`.
public struct Config: Codable {
    public var tenant: String
    public var userId: String
    public var chromeProfile: String
    public var refreshSeconds: Int
    public var weekStartsMonday: Bool
    public var includePending: Bool
    /// Schedule names that mean "company day off" (expected = 0), e.g. "Fridom".
    /// Matched case-insensitively against each day's schedule label.
    public var dayOffScheduleNames: [String]
    /// Show clock-in/out (chronometer) actions in the menu.
    public var enableClockActions: Bool
    /// Compute and show the year-to-date total (one request per month, cached).
    public var enableYearTotal: Bool
    /// Which period the menu-bar number shows (today/week/month/year). Default: week.
    public var barMetric: BarMetric
    /// Clock in / resume as telework (remote) by default.
    public var defaultTelework: Bool
    /// Project id pre-selected for the quick "Check in" item (nil = no project).
    public var defaultProjectId: String?
    /// While the timer is running, count the displayed balances up between refreshes.
    public var liveTick: Bool
    /// When live-ticking, show seconds (`H:MM:SS`) in the menu bar while working.
    public var barShowSecondsWhileWorking: Bool
    /// Which dropdown rows show live seconds while working: `none`/`today`/`all`.
    public var dropdownSecondsScope: DropdownSecondsScope
    /// Which backlog the "Leave by" time clears: `none`/`week`/`month`/`year`.
    public var leaveByScope: LeaveByScope
    /// Send check-in reminders inside `reminderWindows`. Kept separate from the
    /// windows so switching reminders off doesn't lose them.
    public var remindersEnabled: Bool
    /// Time ranges (Europe/Madrid) in which reminders may fire, e.g. "08:00-10:00".
    /// See `Reminders.parseWindow`.
    public var reminderWindows: [String]
    /// Minutes between reminders inside a window.
    public var reminderIntervalMinutes: Int
    /// Optional manual cookie override: `_hcmex_key=...; device_id=...`.
    /// When set, Chrome/Keychain is bypassed entirely.
    public var manualCookie: String?

    public init(tenant: String = "",
                userId: String = "",
                chromeProfile: String = "Default",
                refreshSeconds: Int = 600,
                weekStartsMonday: Bool = true,
                includePending: Bool = true,
                dayOffScheduleNames: [String] = ["Fridom", "Fridom (7 hours)"],
                enableClockActions: Bool = true,
                enableYearTotal: Bool = true,
                barMetric: BarMetric = .week,
                defaultTelework: Bool = true,
                defaultProjectId: String? = nil,
                liveTick: Bool = true,
                barShowSecondsWhileWorking: Bool = false,
                dropdownSecondsScope: DropdownSecondsScope = .today,
                leaveByScope: LeaveByScope = .none,
                remindersEnabled: Bool = true,
                reminderWindows: [String] = ["08:00-10:00", "14:00-15:30"],
                reminderIntervalMinutes: Int = 15,
                manualCookie: String? = nil) {
        self.tenant = tenant
        self.userId = userId
        self.chromeProfile = chromeProfile
        self.refreshSeconds = refreshSeconds
        self.weekStartsMonday = weekStartsMonday
        self.includePending = includePending
        self.dayOffScheduleNames = dayOffScheduleNames
        self.enableClockActions = enableClockActions
        self.enableYearTotal = enableYearTotal
        self.barMetric = barMetric
        self.defaultTelework = defaultTelework
        self.defaultProjectId = defaultProjectId
        self.liveTick = liveTick
        self.barShowSecondsWhileWorking = barShowSecondsWhileWorking
        self.dropdownSecondsScope = dropdownSecondsScope
        self.leaveByScope = leaveByScope
        self.remindersEnabled = remindersEnabled
        self.reminderWindows = reminderWindows
        self.reminderIntervalMinutes = reminderIntervalMinutes
        self.manualCookie = manualCookie
    }

    /// Tolerant decoder: any missing key falls back to its default (keeps old
    /// config.json files working when new fields are added).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        tenant = try c.decodeIfPresent(String.self, forKey: .tenant) ?? d.tenant
        userId = try c.decodeIfPresent(String.self, forKey: .userId) ?? d.userId
        chromeProfile = try c.decodeIfPresent(String.self, forKey: .chromeProfile) ?? d.chromeProfile
        refreshSeconds = try c.decodeIfPresent(Int.self, forKey: .refreshSeconds) ?? d.refreshSeconds
        weekStartsMonday = try c.decodeIfPresent(Bool.self, forKey: .weekStartsMonday) ?? d.weekStartsMonday
        includePending = try c.decodeIfPresent(Bool.self, forKey: .includePending) ?? d.includePending
        dayOffScheduleNames = try c.decodeIfPresent([String].self, forKey: .dayOffScheduleNames) ?? d.dayOffScheduleNames
        enableClockActions = try c.decodeIfPresent(Bool.self, forKey: .enableClockActions) ?? d.enableClockActions
        enableYearTotal = try c.decodeIfPresent(Bool.self, forKey: .enableYearTotal) ?? d.enableYearTotal
        barMetric = try c.decodeIfPresent(BarMetric.self, forKey: .barMetric) ?? d.barMetric
        defaultTelework = try c.decodeIfPresent(Bool.self, forKey: .defaultTelework) ?? d.defaultTelework
        defaultProjectId = try c.decodeIfPresent(String.self, forKey: .defaultProjectId) ?? d.defaultProjectId
        liveTick = try c.decodeIfPresent(Bool.self, forKey: .liveTick) ?? d.liveTick
        barShowSecondsWhileWorking = try c.decodeIfPresent(Bool.self, forKey: .barShowSecondsWhileWorking) ?? d.barShowSecondsWhileWorking
        dropdownSecondsScope = try c.decodeIfPresent(DropdownSecondsScope.self, forKey: .dropdownSecondsScope) ?? d.dropdownSecondsScope
        leaveByScope = try c.decodeIfPresent(LeaveByScope.self, forKey: .leaveByScope) ?? d.leaveByScope
        remindersEnabled = try c.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? d.remindersEnabled
        reminderWindows = try c.decodeIfPresent([String].self, forKey: .reminderWindows) ?? d.reminderWindows
        reminderIntervalMinutes = try c.decodeIfPresent(Int.self, forKey: .reminderIntervalMinutes) ?? d.reminderIntervalMinutes
        manualCookie = try c.decodeIfPresent(String.self, forKey: .manualCookie) ?? d.manualCookie
    }

    public var host: String { "\(tenant).bizneohr.com" }

    public static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("BizneoCompanion", isDirectory: true)
    }
    public static var fileURL: URL { directory.appendingPathComponent("config.json") }

    /// Load config from disk, creating a default file on first run.
    public static func load() -> Config {
        let url = fileURL
        if let data = try? Data(contentsOf: url),
           let cfg = try? JSONDecoder().decode(Config.self, from: data) {
            return cfg
        }
        let cfg = Config()
        try? cfg.save()
        return cfg
    }

    public func save() throws {
        try FileManager.default.createDirectory(at: Config.directory, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: Config.fileURL, options: .atomic)
    }
}
