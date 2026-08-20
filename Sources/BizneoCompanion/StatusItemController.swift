import Foundation
import Cocoa
import BizneoCore

/// Owns the menu-bar status item and drives periodic refreshes.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var config: Config
    private var client: BizneoClient
    private var timer: Timer?
    private var lastError: String?
    private var clockBusy = false
    private var lastRefreshAt: Date?
    private var displayTimer: Timer?
    /// Period stats + their menu items, for in-place live-tick updates.
    /// `secondsLive` = show H:MM:SS while the timer runs (Today only).
    private var periodRows: [(stat: PeriodStat, item: NSMenuItem, secondsLive: Bool)] = []

    init(config: Config) {
        self.config = config
        self.client = BizneoClient(config: config)
        super.init()
    }

    func start() {
        menu.autoenablesItems = false
        statusItem.menu = menu
        setStatus(look: .loading, text: "", color: .secondaryLabelColor, dimText: true)
        rebuildMenu(snapshot: nil)
        scheduleTimer()
        refresh()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = TimeInterval(max(60, config.refreshSeconds))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    // MARK: - Refresh

    func refresh() {
        // Fade the current content while the request is in flight; keep the icon so
        // the item doesn't flicker on every refresh cycle.
        if let c = barContent() {
            setStatus(look: c.look, text: c.text, color: c.color, dimText: true)
        } else {
            setStatus(look: .loading, text: "", color: .secondaryLabelColor, dimText: true)
        }
        Task { @MainActor in
            do {
                let snap = try await client.refresh()
                self.lastError = nil
                self.apply(snap)
            } catch {
                self.client.invalidateCookie()
                self.lastError = (error as? BizneoError)?.errorDescription ?? error.localizedDescription
                self.applyError()
            }
        }
    }

    private var latest: Snapshot?
    private func apply(_ snap: Snapshot) {
        latest = snap
        lastRefreshAt = snap.generatedAt
        refreshTitle()
        rebuildMenu(snapshot: snap)
        startOrStopDisplayTimer()
    }

    // MARK: - Live tick

    /// Whether the chronometer is currently running.
    ///
    /// Not gated on `enableClockActions`: that flag decides whether *we* may clock
    /// in/out, but the Bizneo timer runs (and the balance grows) either way.
    private var isWorking: Bool {
        latest?.chrono?.status == .working
    }

    /// Whether displayed values should count up between refreshes.
    private var isLive: Bool { config.liveTick && isWorking }

    /// Live projected balance for a period, in seconds (adds time since last refresh
    /// while the timer runs).
    private func liveSeconds(_ s: PeriodStat) -> Int {
        let elapsed = isLive ? Int(Date().timeIntervalSince(lastRefreshAt ?? Date())) : 0
        return s.liveSeconds(working: isLive, elapsedSinceRefresh: elapsed)
    }

    private func colorForSeconds(_ secs: Int) -> NSColor {
        secs < 0 ? .systemRed : (secs > 0 ? .systemGreen : .labelColor)
    }

    /// Menu-bar text for a period's live balance (H:MM, or H:MM:SS when configured).
    private func barText(_ s: PeriodStat) -> String {
        let secs = liveSeconds(s)
        if isLive && config.barShowSecondsWhileWorking {
            return TimeFmt.signedHMS(secs)
        }
        let sign = secs < 0 ? -1 : 1
        return TimeFmt.signed(sign * (abs(secs) / 60))
    }

    private func refreshTitle() {
        guard let c = barContent() else { return }
        setStatus(look: c.look, text: c.text, color: c.color, dimText: false)
    }

    private func startOrStopDisplayTimer() {
        if isLive {
            guard displayTimer == nil else { return }
            let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(t, forMode: .common)
            displayTimer = t
        } else {
            displayTimer?.invalidate()
            displayTimer = nil
        }
    }

    private func tick() {
        guard isLive else { startOrStopDisplayTimer(); return }
        refreshTitle()
        for row in periodRows { row.item.title = periodTitleString(row.stat, secondsLive: row.secondsLive) }
    }

    // MARK: - Bar appearance

    /// How a `BarState` presents in the menu bar.
    private struct BarLook {
        /// SF Symbol name; nil = no icon at all.
        var symbol: String?
        /// Emoji used when the symbol isn't available on this macOS version.
        var fallback: String
        /// nil = template image, i.e. it follows the menu-bar tint and dark mode.
        /// A colour makes the icon stand out — reserved for states needing action.
        var tint: NSColor?
        /// Fade the balance text (states where nothing is expected of you).
        var dim: Bool = false
        /// Tooltip + VoiceOver description.
        var label: String

        static let loading = BarLook(symbol: "hourglass", fallback: "⏳", tint: nil, dim: true,
                                     label: "Loading…")
        static let error = BarLook(symbol: "exclamationmark.triangle.fill", fallback: "⚠︎",
                                   tint: .systemOrange, label: "Couldn't reach Bizneo")
    }

    /// Icon table. The icon carries the *clock state*; the text keeps carrying the
    /// balance sign in red/green, so the two never compete. Orange appears in the
    /// bar only when something is actually owed.
    private func look(for state: BarState) -> BarLook {
        switch state {
        case .working:
            return BarLook(symbol: "play.circle.fill", fallback: "●", tint: nil,
                           label: "Clocked in — timer running")
        case .onBreak:
            return BarLook(symbol: "pause.circle.fill", fallback: "⏸", tint: nil,
                           label: "On a break — timer paused")
        case .notCheckedIn:
            return BarLook(symbol: "clock.badge.exclamationmark", fallback: "⚠︎", tint: .systemOrange,
                           label: "Not clocked in — you owe hours today")
        case .checkedOutEarly:
            return BarLook(symbol: "stop.circle", fallback: "○", tint: nil, dim: true,
                           label: "Checked out — today's target not met")
        case .doneForToday:
            return BarLook(symbol: "checkmark.circle", fallback: "✓", tint: nil, dim: true,
                           label: "Checked out — today complete")
        case .offDuty:
            return BarLook(symbol: nil, fallback: "", tint: nil, dim: true,
                           label: "No hours expected today")
        case .unknown:
            return BarLook(symbol: "questionmark.circle", fallback: "?", tint: nil, dim: true,
                           label: "Clock state unknown — Bizneo's markup may have changed")
        }
    }

    /// Icon + text + colour for the current snapshot, or nil before the first one.
    private func barContent() -> (look: BarLook, text: String, color: NSColor)? {
        guard let s = latest else { return nil }
        let state = s.barState
        // The one state worth shouting about: swap the balance for a call to action
        // so the item changes *shape*, not just gains a mark. Suppressed when the
        // app may not clock in for you — then the icon alone carries the warning.
        if state.needsAttention && config.enableClockActions {
            return (look(for: state), "Check in", .systemOrange)
        }
        let stat = s.stat(for: config.barMetric)
        return (look(for: state), barText(stat), colorForSeconds(liveSeconds(stat)))
    }

    private func applyError() {
        displayTimer?.invalidate()
        displayTimer = nil
        var errorLook = BarLook.error
        if let err = lastError { errorLook.label = err }
        setStatus(look: errorLook, text: "", color: .systemOrange, dimText: false)
        rebuildMenu(snapshot: latest)
    }

    // MARK: - Status item rendering

    /// Draw the status item: leading SF Symbol plus the balance text.
    private func setStatus(look: BarLook, text: String, color: NSColor, dimText: Bool) {
        guard let button = statusItem.button else { return }
        var title = text
        if let name = look.symbol, let img = barIcon(name, tint: look.tint, description: look.label) {
            button.image = img
            button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
            button.imageHugsTitle = true
        } else {
            // No symbol, or unavailable on this macOS: fall back to the emoji glyph.
            button.image = nil
            button.imagePosition = .noImage
            if look.symbol != nil && !look.fallback.isEmpty {
                title = title.isEmpty ? look.fallback : look.fallback + " " + title
            }
        }
        let faded = dimText || look.dim
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: faded ? color.withAlphaComponent(0.5) : color,
        ])
        button.toolTip = look.label
    }

    /// An SF Symbol sized to sit next to the 13pt title. Template unless tinted, so
    /// it follows the menu-bar appearance (dark mode, tinting, reduce transparency).
    /// Returns nil when the symbol is unavailable, so callers can fall back.
    private func barIcon(_ name: String, tint: NSColor?, description: String) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: description) else { return nil }
        var cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        if let tint { cfg = cfg.applying(NSImage.SymbolConfiguration(hierarchicalColor: tint)) }
        guard let img = base.withSymbolConfiguration(cfg) else { return nil }
        img.isTemplate = (tint == nil)   // tinted images must opt out of templating
        img.accessibilityDescription = description
        return img
    }

    // MARK: - Menu

    private func rebuildMenu(snapshot: Snapshot?) {
        menu.removeAllItems()
        periodRows.removeAll()

        if let s = snapshot {
            menu.addItem(header("Bizneo Companion"))
            menu.addItem(periodItem(s.today, isToday: true))
            menu.addItem(periodItem(s.week))
            menu.addItem(periodItem(s.month))
            if let year = s.year { menu.addItem(periodItem(year)) }

            if config.enableClockActions, let chrono = s.chrono {
                menu.addItem(.separator())
                addClockSection(chrono, state: s.barState, today: s.today)
            }

            let pend = s.pending.filter { $0.proposedMin != nil }
            if config.includePending && !pend.isEmpty {
                menu.addItem(.separator())
                let head = NSMenuItem(title: "Pending changes (\(pend.count))", action: nil, keyEquivalent: "")
                let sub = NSMenu()
                for p in pend.sorted(by: { $0.dateString < $1.dateString }) {
                    sub.addItem(pendingItem(p))
                }
                head.submenu = sub
                menu.addItem(head)
            }

            menu.addItem(.separator())
            menu.addItem(info("Updated \(timeString(s.generatedAt))"))
        } else if let err = lastError {
            menu.addItem(header("Bizneo Companion"))
            menu.addItem(info("⚠︎ \(err)"))
            if err.contains("logged in") || err.contains("cookie") {
                menu.addItem(actionItem("Open Bizneo to log in", #selector(openBizneo)))
            }
            menu.addItem(.separator())
        } else {
            menu.addItem(info("Loading…"))
            menu.addItem(.separator())
        }

        menu.addItem(actionItem("Refresh now", #selector(refreshNow), key: "r"))
        menu.addItem(actionItem("Open Bizneo timesheet", #selector(openBizneo)))
        menu.addItem(actionItem("Edit configuration…", #selector(openConfig)))
        menu.addItem(.separator())
        menu.addItem(actionItem("Quit", #selector(quit), key: "q"))
    }

    private func periodItem(_ s: PeriodStat, isToday: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: periodTitleString(s, secondsLive: isToday), action: nil, keyEquivalent: "")
        item.isEnabled = true
        if s.hasPending {
            item.toolTip = "Includes \(TimeFmt.signed(s.pendingDeltaMin)) of pending (unapproved) changes."
        }
        periodRows.append((s, item, isToday))
        return item
    }

    /// Title for a period row. Seconds (H:MM:SS) tick while the timer runs per
    /// `config.dropdownSecondsScope` (`none`/`today`/`all`); otherwise H:MM.
    private func periodTitleString(_ s: PeriodStat, secondsLive: Bool) -> String {
        let secs = liveSeconds(s)
        let dot = secs < 0 ? Glyph.behind : (secs > 0 ? Glyph.ahead : Glyph.level)
        let verb = secs < 0 ? "missing" : "ahead"
        let showSeconds = isLive && {
            switch config.dropdownSecondsScope {
            case .none:  return false
            case .today: return secondsLive   // true only for the Today row
            case .all:   return true
            }
        }()
        let mag = showSeconds ? hmsMagnitude(secs) : TimeFmt.plain(abs(secs) / 60)
        var title = "\(dot)\(s.label):  \(verb) \(mag)"
        if s.hasPending {
            title += "   (official \(TimeFmt.signed(s.officialBalanceMin)), pending \(TimeFmt.signed(s.pendingDeltaMin)))"
        }
        return title
    }

    private func hmsMagnitude(_ secs: Int) -> String {
        let a = abs(secs)
        return String(format: "%d:%02d:%02d", a / 3600, (a % 3600) / 60, a % 60)
    }

    // MARK: - Clock (chronometer) section

    /// Dropdown glyphs, in one place so every row agrees. (The menu bar itself uses
    /// SF Symbols — see `look(for:)` — but `NSMenuItem` titles stay plain text.)
    private enum Glyph {
        static let behind = "🔴 "
        static let ahead = "🟢 "
        static let level = "⚪️ "
        static let working = "🟢"
        static let onBreak = "⏸"
        static let notCheckedIn = "⚠︎"
        static let stopped = "○"
        static let done = "✓"
        static let unknown = "?"
        static let leaveBy = "🏁"
    }

    /// Last project id used for check-in (persisted in UserDefaults).
    private var lastProjectId: String? {
        get { UserDefaults.standard.string(forKey: "lastProjectId") }
        set { UserDefaults.standard.set(newValue, forKey: "lastProjectId") }
    }

    private var modeLabel: String { config.defaultTelework ? "telework" : "office" }

    private func projectName(_ id: String?, in projects: [ChronoProject]) -> String {
        guard let id, !id.isEmpty else { return "no project" }
        return projects.first(where: { $0.id == id })?.name ?? "project \(id)"
    }

    /// One-line summary of a stopped clock. Bizneo reports "never checked in" and
    /// "checked out" as the same `.stopped` status, so `BarState` is what tells
    /// "you forgot" apart from "you're done".
    private func stoppedSummary(_ state: BarState, today: PeriodStat) -> String {
        let missing = TimeFmt.plain(max(0, -today.projectedBalanceMin))
        switch state {
        case .notCheckedIn:
            return "\(Glyph.notCheckedIn) Not clocked in · missing \(missing) today"
        case .checkedOutEarly:
            return "\(Glyph.stopped) Checked out · logged \(TimeFmt.plain(today.loggedMin)), missing \(missing)"
        case .doneForToday:
            return "\(Glyph.done) Checked out · today complete"
        case .offDuty:
            return "\(Glyph.stopped) No hours expected today"
        default:
            return "\(Glyph.stopped) Not clocked in"   // unreachable: clock is running
        }
    }

    private func addClockSection(_ chrono: ChronoState, state: BarState, today: PeriodStat) {
        let busy = clockBusy
        switch state {
        case .working:
            let since = chrono.startedAt.flatMap(clockTime(_:))
            menu.addItem(info("\(Glyph.working) Working (\(modeLabel))" + (since.map { " · since \($0)" } ?? "")))
            if let leaveBy = expectedCheckoutText() {
                menu.addItem(info("\(Glyph.leaveBy) Leave by \(leaveBy)"))
            }
            menu.addItem(actionItem("Take break", #selector(takeBreak), enabled: !busy))
            menu.addItem(actionItem("Check out…", #selector(checkOut), enabled: !busy))
        case .onBreak:
            let since = chrono.startedAt.flatMap(clockTime(_:))
            menu.addItem(info("\(Glyph.onBreak) On break" + (since.map { " · since \($0)" } ?? "")))
            menu.addItem(actionItem("Resume", #selector(resumeWork), enabled: !busy))
            menu.addItem(actionItem("Check out…", #selector(checkOut), enabled: !busy))
        case .notCheckedIn, .checkedOutEarly, .doneForToday, .offDuty:
            menu.addItem(info(stoppedSummary(state, today: today)))
            // Quick check-in with the last-used (or configured default) project.
            let quickId = lastProjectId ?? config.defaultProjectId
            let quick = actionItem("Check in · \(projectName(quickId, in: chrono.projects)) (\(modeLabel))",
                                   #selector(checkInQuick), enabled: !busy)
            menu.addItem(quick)
            // Full picker.
            let checkIn = NSMenuItem(title: "Check in (\(modeLabel)) ▸", action: nil, keyEquivalent: "")
            checkIn.isEnabled = !busy
            let sub = NSMenu()
            let none = NSMenuItem(title: "No project", action: #selector(checkInProject(_:)), keyEquivalent: "")
            none.target = self; none.representedObject = ""; none.isEnabled = !busy
            sub.addItem(none)
            if !chrono.projects.isEmpty { sub.addItem(.separator()) }
            for p in chrono.projects {
                let it = NSMenuItem(title: p.name, action: #selector(checkInProject(_:)), keyEquivalent: "")
                it.target = self; it.representedObject = p.id; it.isEnabled = !busy
                sub.addItem(it)
            }
            checkIn.submenu = sub
            menu.addItem(checkIn)
        case .unknown:
            // Previously the whole section was hidden here, which made a Bizneo
            // markup change impossible to spot. Say so instead.
            menu.addItem(info("\(Glyph.unknown) Clock state unknown"))
        }
        if busy { menu.addItem(info("   …working…")) }
    }

    private func pendingItem(_ p: PendingRequest) -> NSMenuItem {
        let when = prettyDate(p.dateString)
        let proposed = p.proposedMin.map { TimeFmt.plain($0) } ?? "?"
        let delta = TimeFmt.signed(p.deltaMin)
        let item = NSMenuItem(title: "\(when): proposes \(proposed)  (\(delta))",
                              action: #selector(openRequest(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = p.id
        item.toolTip = "Awaiting approval — click to open in Bizneo."
        return item
    }

    private func header(_ t: String) -> NSMenuItem {
        let i = NSMenuItem(title: t, action: nil, keyEquivalent: "")
        i.attributedTitle = NSAttributedString(string: t, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        i.isEnabled = false
        return i
    }

    private func info(_ t: String) -> NSMenuItem {
        let i = NSMenuItem(title: t, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    private func actionItem(_ t: String, _ sel: Selector, key: String = "", enabled: Bool = true) -> NSMenuItem {
        let i = NSMenuItem(title: t, action: sel, keyEquivalent: key)
        i.target = self
        i.isEnabled = enabled
        return i
    }

    // MARK: - Clock actions

    @objc private func takeBreak() { doClock(.takeBreak) }
    @objc private func resumeWork() { doClock(.resume) }

    @objc private func checkInProject(_ sender: NSMenuItem) {
        let pid = (sender.representedObject as? String) ?? ""
        lastProjectId = pid
        doClock(.checkIn(projectIds: pid.isEmpty ? [] : [pid], telework: config.defaultTelework))
    }

    @objc private func checkInQuick() {
        let pid = lastProjectId ?? config.defaultProjectId ?? ""
        doClock(.checkIn(projectIds: pid.isEmpty ? [] : [pid], telework: config.defaultTelework))
    }

    // MARK: - Alerts

    /// A tinted SF Symbol sized for an NSAlert's 64pt icon well.
    /// Returns nil when the symbol is unavailable, in which case the caller leaves
    /// `alert.icon` untouched and AppKit keeps its default.
    private func alertIcon(_ name: String, color: NSColor) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let cfg = NSImage.SymbolConfiguration(pointSize: 48, weight: .regular)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: color))
        let img = base.withSymbolConfiguration(cfg)
        img?.isTemplate = false   // keep the tint; symbol images default to template
        return img
    }

    @objc private func checkOut() {
        let alert = NSAlert()
        alert.messageText = "Check out?"
        alert.informativeText = "This will stop your Bizneo timer for today."
        alert.addButton(withTitle: "Check out")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if let icon = alertIcon("figure.walk.departure", color: .systemOrange) { alert.icon = icon }
        if alert.runModal() == .alertFirstButtonReturn {
            doClock(.checkOut)
        }
    }

    private func doClock(_ action: ChronoAction) {
        guard !clockBusy else { return }
        clockBusy = true
        rebuildMenu(snapshot: latest)
        Task { @MainActor in
            defer { clockBusy = false }
            do {
                _ = try await client.performChrono(action)
                self.refresh()   // reload state + balances
            } catch {
                self.lastError = (error as? BizneoError)?.errorDescription ?? error.localizedDescription
                let alert = NSAlert()
                alert.messageText = "Clock action failed"
                alert.informativeText = self.lastError ?? "Unknown error"
                alert.alertStyle = .critical
                if let icon = self.alertIcon("exclamationmark.triangle.fill", color: .systemRed) { alert.icon = icon }
                alert.runModal()
                self.rebuildMenu(snapshot: self.latest)
            }
        }
    }

    /// Format a chrono "data-from" like "2026-6-22 15:10:07" → "15:10".
    private func clockTime(_ s: String) -> String? {
        let parts = s.split(separator: " ")
        guard parts.count == 2 else { return nil }
        let hms = parts[1].split(separator: ":")
        guard hms.count >= 2 else { return nil }
        return "\(hms[0]):\(hms[1])"
    }

    /// Wall-clock time the user can leave to hit today's target ("HH:MM"), or nil
    /// when already at/over target. Anchored on the last refresh's snapshot, so it
    /// stays constant between refreshes.
    private func expectedCheckoutText() -> String? {
        guard let s = latest,
              let checkout = Calculator.expectedCheckout(today: s.today, generatedAt: s.generatedAt)
        else { return nil }
        let cal = Calculator.madridCalendar(weekStartsMonday: config.weekStartsMonday)
        return TimeFmt.clock(checkout, calendar: cal)
    }

    // MARK: - Actions

    @objc private func refreshNow() { refresh() }

    @objc private func openBizneo() {
        if let url = URL(string: "https://\(config.host)/time-attendance/my-logs/\(config.userId)") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openRequest(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let url = URL(string: "https://\(config.host)/time-attendance/logged-time-requests/\(id)") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openConfig() {
        try? FileManager.default.createDirectory(at: Config.directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: Config.fileURL.path) { try? config.save() }
        NSWorkspace.shared.open(Config.fileURL)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Date helpers

    private func timeString(_ d: Date) -> String {
        let f = DateFormatter(); f.timeZone = TimeZone(identifier: "Europe/Madrid"); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
    private func prettyDate(_ ymd: String) -> String {
        let inF = DateFormatter(); inF.dateFormat = "yyyy-MM-dd"; inF.timeZone = TimeZone(identifier: "Europe/Madrid")
        guard let d = inF.date(from: ymd) else { return ymd }
        let outF = DateFormatter(); outF.dateFormat = "EEE d MMM"; outF.timeZone = TimeZone(identifier: "Europe/Madrid")
        return outF.string(from: d)
    }
}
