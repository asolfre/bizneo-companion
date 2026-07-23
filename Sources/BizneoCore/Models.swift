import Foundation

/// One day's row parsed from the "My timesheet" (my-logs) page.
public struct DayLog: Equatable {
    public var dateString: String          // "yyyy-MM-dd"
    public var scheduleName: String?       // schedule label, e.g. "Mon-Thu", "Friday", "Fridom"
    public var expectedMin: Int?           // expected work minutes (from the "Expected" column range)
    public var loggedMin: Int?             // currently counted logged total (the "Total" column)
    public var balanceMin: Int?            // signed balance = logged - expected (from the balance tag)
    public var pendingRequestId: String?   // id if a pending change-request ("View request") exists

    public init(dateString: String, scheduleName: String? = nil, expectedMin: Int? = nil,
                loggedMin: Int? = nil, balanceMin: Int? = nil, pendingRequestId: String? = nil) {
        self.dateString = dateString
        self.scheduleName = scheduleName
        self.expectedMin = expectedMin
        self.loggedMin = loggedMin
        self.balanceMin = balanceMin
        self.pendingRequestId = pendingRequestId
    }

    /// Whether this day's schedule marks it as a company day off (e.g. "Fridom").
    public func isDayOff(_ dayOffNames: [String]) -> Bool {
        guard let name = scheduleName?.trimmingCharacters(in: .whitespaces).lowercased() else { return false }
        return dayOffNames.contains { $0.trimmingCharacters(in: .whitespaces).lowercased() == name }
    }

    /// Minutes to add back so a company day off (e.g. "Fridom") doesn't count as
    /// missing time. Only applied when the day actually carries a balance/deficit:
    /// if Bizneo shows no balance for the day it's already excluded (0), so adding
    /// the expected hours would wrongly credit it as overtime.
    public func dayOffCorrection(_ dayOffNames: [String]) -> Int {
        guard isDayOff(dayOffNames), balanceMin != nil else { return 0 }
        return expectedMin ?? 0
    }
}

/// A pending "Request for change in the time logs" awaiting approval.
public struct PendingRequest: Equatable {
    public var id: String
    public var dateString: String
    public var proposedMin: Int?       // proposed total duration if approved
    public var currentLoggedMin: Int?  // what is counted now for that day
    public var state: String?          // e.g. "pending" if exposed by the detail page

    public init(id: String, dateString: String, proposedMin: Int? = nil,
                currentLoggedMin: Int? = nil, state: String? = nil) {
        self.id = id
        self.dateString = dateString
        self.proposedMin = proposedMin
        self.currentLoggedMin = currentLoggedMin
        self.state = state
    }

    /// Extra minutes this request adds vs. what's currently counted.
    public var deltaMin: Int {
        guard let p = proposedMin else { return 0 }
        return p - (currentLoggedMin ?? 0)
    }
}

/// Aggregated figures for one period (today / week / month).
public struct PeriodStat {
    public var label: String
    public var loggedMin: Int
    public var expectedMin: Int
    public var officialBalanceMin: Int   // from Bizneo (excludes pending). Negative = behind.
    public var pendingDeltaMin: Int      // sum of pending deltas falling in this period

    public init(label: String, loggedMin: Int = 0, expectedMin: Int = 0,
                officialBalanceMin: Int = 0, pendingDeltaMin: Int = 0) {
        self.label = label
        self.loggedMin = loggedMin
        self.expectedMin = expectedMin
        self.officialBalanceMin = officialBalanceMin
        self.pendingDeltaMin = pendingDeltaMin
    }

    /// Balance including pending changes (what the user asked for).
    public var projectedBalanceMin: Int { officialBalanceMin + pendingDeltaMin }
    public var hasPending: Bool { pendingDeltaMin != 0 }

    /// Live projected balance in **seconds**: the projected balance plus, while the
    /// timer is running, the seconds elapsed since the last refresh (every period
    /// includes today's running session after reconciliation).
    public func liveSeconds(working: Bool, elapsedSinceRefresh: Int) -> Int {
        projectedBalanceMin * 60 + (working ? max(0, elapsedSinceRefresh) : 0)
    }
}

/// Full result of one refresh.
public struct Snapshot {
    public var today: PeriodStat
    public var week: PeriodStat
    public var month: PeriodStat
    public var year: PeriodStat?
    public var pending: [PendingRequest]
    public var monthLoggedMin: Int?
    public var chrono: ChronoState?
    public var generatedAt: Date

    public init(today: PeriodStat, week: PeriodStat, month: PeriodStat,
                year: PeriodStat? = nil,
                pending: [PendingRequest], monthLoggedMin: Int?,
                chrono: ChronoState? = nil, generatedAt: Date) {
        self.today = today
        self.week = week
        self.month = month
        self.year = year
        self.pending = pending
        self.monthLoggedMin = monthLoggedMin
        self.chrono = chrono
        self.generatedAt = generatedAt
    }

    /// The period stat the menu bar should show for the given metric.
    public func stat(for metric: BarMetric) -> PeriodStat {
        switch metric {
        case .today: return today
        case .week: return week
        case .month: return month
        case .year: return year ?? month
        }
    }
}

/// Errors surfaced to the UI.
public enum BizneoError: Error, LocalizedError {
    case notAuthenticated
    case cookieUnavailable(String)
    case http(Int, String)
    case network(String)
    case parse(String)

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not logged in to Bizneo (open it in Chrome)"
        case .cookieUnavailable(let m): return "Couldn't read Chrome cookie: \(m)"
        case .http(let c, _): return "Bizneo returned HTTP \(c)"
        case .network(let m): return "Network error: \(m)"
        case .parse(let m): return "Couldn't read timesheet: \(m)"
        }
    }
}

// ─── Chronometer (clock in/out) ──────────────────────────────────────────────

public enum ChronoStatus: String, Equatable {
    case stopped   // not clocked in → can Check in
    case working   // clocked in     → can Break / Check out
    case paused    // on a break     → can Resume / Check out
    case unknown
}

public struct ChronoProject: Equatable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

/// Current chronometer state parsed from a `#chronometer-wrapper` fragment.
public struct ChronoState: Equatable {
    public var status: ChronoStatus
    public var chronoId: String?     // id of the active chrono (working/paused)
    public var shiftId: String?
    public var csrfToken: String?
    public var formId: String?       // e.g. "chrono-form-hub_chrono" (for hx-trigger)
    public var startedAt: String?    // data-from, e.g. "2026-6-22 15:10:07"
    public var projects: [ChronoProject]

    public init(status: ChronoStatus, chronoId: String? = nil, shiftId: String? = nil,
                csrfToken: String? = nil, formId: String? = nil, startedAt: String? = nil,
                projects: [ChronoProject] = []) {
        self.status = status
        self.chronoId = chronoId
        self.shiftId = shiftId
        self.csrfToken = csrfToken
        self.formId = formId
        self.startedAt = startedAt
        self.projects = projects
    }
}

/// A clock action the user can trigger.
public enum ChronoAction: Equatable {
    case checkIn(projectIds: [String], telework: Bool)
    case takeBreak
    case resume
    case checkOut
}

