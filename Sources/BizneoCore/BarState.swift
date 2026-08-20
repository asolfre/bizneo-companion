import Foundation

/// What the menu bar should communicate about the clock, derived from the
/// chronometer status plus today's figures.
///
/// Bizneo has no "checked out" state — the `#chronometer-wrapper` fragment returns
/// the same start form before the first check-in and after checkout, so both arrive
/// here as `ChronoStatus.stopped` (see `Models.swift`, `ChronoStatus`). The three
/// stopped sub-states below are therefore *inferred* from `today`.
public enum BarState: String, Equatable {
    /// The chronometer is running.
    case working
    /// The chronometer is paused (on a break).
    case onBreak
    /// Hours are expected today, none logged, clock not running → you forgot.
    case notCheckedIn
    /// Some time logged today and the clock is off, but the target isn't met.
    case checkedOutEarly
    /// Clock off and today's target is already met (or exceeded).
    case doneForToday
    /// No hours expected today: weekend, holiday or a company day off.
    case offDuty
    /// The chronometer state couldn't be determined (parser out of date).
    case unknown

    /// Whether this state means "you owe time today and the clock isn't running".
    /// `notCheckedIn` is the loud one; `checkedOutEarly` is the same fact after a
    /// deliberate stop, so it stays quiet.
    public var needsAttention: Bool { self == .notCheckedIn }

    /// Derive the display state. Pure: no I/O, no clock reads.
    ///
    /// - Parameters:
    ///   - chrono: parsed chronometer status; `nil` before the first refresh.
    ///   - today: today's figures (`Snapshot.today`) — **not** the period selected
    ///     by `Config.barMetric`, so a healthy weekly total can't mask a forgotten
    ///     check-in today.
    public static func derive(chrono: ChronoStatus?, today: PeriodStat) -> BarState {
        switch chrono {
        case .working: return .working
        case .paused: return .onBreak
        case .unknown, .none: return .unknown
        case .stopped:
            // No expected hours → nothing to nag about. Also the safe default when
            // neither hub_chrono nor a my-logs row exists for today (all-zero stat).
            if today.expectedMin <= 0 { return .offDuty }
            // Projected (not official) balance, to agree with the "missing" figure
            // on the Today row and with Calculator.expectedCheckout.
            if today.projectedBalanceMin >= 0 { return .doneForToday }
            return today.loggedMin > 0 ? .checkedOutEarly : .notCheckedIn
        }
    }
}

extension Snapshot {
    /// The clock state the menu bar should reflect for this snapshot.
    public var barState: BarState { BarState.derive(chrono: chrono?.status, today: today) }
}
