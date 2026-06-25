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
        setTitle("⏳", color: .secondaryLabelColor)
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
        setTitle(currentTitleText() ?? "⏳", color: .secondaryLabelColor, dim: true)
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
    private var isWorking: Bool {
        config.enableClockActions && latest?.chrono?.status == .working
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
        guard let s = latest else { return }
        let stat = s.stat(for: config.barMetric)
        setTitle(clockGlyph(s.chrono) + barText(stat), color: colorForSeconds(liveSeconds(stat)))
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

    /// Small leading glyph showing clock state: ● working, ⏸ break, (none) stopped.
    private func clockGlyph(_ chrono: ChronoState?) -> String {
        guard config.enableClockActions, let c = chrono else { return "" }
        switch c.status {
        case .working: return "● "
        case .paused: return "⏸ "
        default: return ""
        }
    }

    private func applyError() {
        displayTimer?.invalidate()
        displayTimer = nil
        setTitle("⚠︎", color: .systemOrange)
        rebuildMenu(snapshot: latest)
    }

    private func currentTitleText() -> String? {
        guard let s = latest else { return nil }
        return barText(s.stat(for: config.barMetric))
    }

    // MARK: - Title

    private func setTitle(_ text: String, color: NSColor, dim: Bool = false) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: dim ? color.withAlphaComponent(0.5) : color,
        ]
        statusItem.button?.attributedTitle = NSAttributedString(string: text, attributes: attrs)
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

            if config.enableClockActions, let chrono = s.chrono, chrono.status != .unknown {
                menu.addItem(.separator())
                addClockSection(chrono)
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

    /// Title for a period row. The Today row ticks in H:MM:SS while the timer runs;
    /// other rows show H:MM (live at minute resolution).
    private func periodTitleString(_ s: PeriodStat, secondsLive: Bool) -> String {
        let secs = liveSeconds(s)
        let dot = secs < 0 ? "🔴 " : (secs > 0 ? "🟢 " : "⚪️ ")
        let verb = secs < 0 ? "missing" : "ahead"
        let mag = (isLive && secondsLive) ? hmsMagnitude(secs) : TimeFmt.plain(abs(secs) / 60)
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

    private func addClockSection(_ chrono: ChronoState) {
        let busy = clockBusy
        switch chrono.status {
        case .working:
            let since = chrono.startedAt.flatMap(clockTime(_:))
            menu.addItem(info("🟢 Working (\(modeLabel))" + (since.map { " · since \($0)" } ?? "")))
            menu.addItem(actionItem("Take break", #selector(takeBreak), enabled: !busy))
            menu.addItem(actionItem("Check out…", #selector(checkOut), enabled: !busy))
        case .paused:
            let since = chrono.startedAt.flatMap(clockTime(_:))
            menu.addItem(info("⏸ On break" + (since.map { " · since \($0)" } ?? "")))
            menu.addItem(actionItem("Resume", #selector(resumeWork), enabled: !busy))
            menu.addItem(actionItem("Check out…", #selector(checkOut), enabled: !busy))
        case .stopped:
            menu.addItem(info("○ Not clocked in"))
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
            break
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

    @objc private func checkOut() {
        let alert = NSAlert()
        alert.messageText = "Check out?"
        alert.informativeText = "This will stop your Bizneo timer for today."
        alert.addButton(withTitle: "Check out")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
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
