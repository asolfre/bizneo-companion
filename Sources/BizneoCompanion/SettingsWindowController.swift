import Cocoa
import ServiceManagement
import SwiftUI
import BizneoCore

/// The Settings window, replacing the old "Edit configuration…" (which just opened
/// the raw `config.json`).
///
/// SwiftUI rather than the hand-built `NSGridView` the plan first sketched: a `Form`
/// is roughly a third of the code for seventeen fields, and the toolchain constraint
/// that ruled out xibs (Command Line Tools, no Xcode) doesn't apply here — the
/// SwiftUI module ships in the CLT SDK. Plain `@State` only: `@Observable` needs the
/// swift-syntax macros, which a CLT-only toolchain can't build.
///
/// See `docs/plans/done/add-settings-screen.md`.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let onSave: (Config) -> Void

    init(onSave: @escaping (Config) -> Void) {
        self.onSave = onSave
    }

    /// Show the window, seeded with the live config and the projects from the latest
    /// snapshot. Already on screen → just bring it forward, so a second click doesn't
    /// discard half-typed edits. Otherwise the hosting controller is rebuilt: reusing
    /// it would keep SwiftUI's `@State`, so a cancelled edit would reappear on reopen.
    func show(config: Config, projects: [ChronoProject]) {
        if let w = window, w.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }
        let root = SettingsView(
            config: config,
            projects: projects,
            onSave: { [weak self] new in
                self?.onSave(new)
                self?.close()
            },
            onCancel: { [weak self] in self?.close() }
        )

        let w: NSWindow
        if let existing = window {
            w = existing
        } else {
            w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
                         styleMask: [.titled, .closable],
                         backing: .buffered,
                         defer: false)
            w.title = "\(AppInfo.name) Settings"
            w.isReleasedWhenClosed = false   // we hold the only strong reference
            w.center()
            window = w
        }
        w.contentViewController = NSHostingController(rootView: root)
        // An .accessory app has no Dock icon, so the window needs an explicit
        // activation to come to the front.
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private func close() { window?.close() }
}

// MARK: - Form

private struct SettingsView: View {
    @State private var cfg: Config
    /// `dayOffScheduleNames` is edited as one comma-separated field and split on save.
    @State private var dayOffText: String
    /// `reminderWindows`, edited as one comma-separated field like `dayOffText`.
    @State private var remindersText: String
    @State private var notificationsDenied = false
    @State private var openAtLogin: Bool
    @State private var loginNeedsApproval: Bool
    @State private var loginError: String?

    private let projects: [ChronoProject]
    private let onSave: (Config) -> Void
    private let onCancel: () -> Void

    init(config: Config,
         projects: [ChronoProject],
         onSave: @escaping (Config) -> Void,
         onCancel: @escaping () -> Void) {
        _cfg = State(initialValue: config)
        _dayOffText = State(initialValue: config.dayOffScheduleNames.joined(separator: ", "))
        _remindersText = State(initialValue: config.reminderWindows.joined(separator: ", "))
        let login = Self.loginState()
        _openAtLogin = State(initialValue: login.on)
        _loginNeedsApproval = State(initialValue: login.needsApproval)
        self.projects = projects
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                accountSection
                displaySection
                clockSection
                remindersSection
                timeOffSection
                generalSection
                advancedSection
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Text("v\(AppInfo.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(12)
        }
        .frame(width: 480, height: 600)
    }

    // MARK: Sections

    private var accountSection: some View {
        Section("Account") {
            TextField("Tenant", text: $cfg.tenant, prompt: Text("your-company"))
            TextField("User ID", text: $cfg.userId, prompt: Text("123456"))
            TextField("Chrome profile", text: $cfg.chromeProfile, prompt: Text("Default"))
            Text("The profile directory name, e.g. `Default` or `Profile 1` — find it at chrome://version under Profile Path.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var displaySection: some View {
        Section("Display") {
            Picker("Menu bar shows", selection: $cfg.barMetric) {
                ForEach(BarMetric.allCases, id: \.self) { Text(label($0)).tag($0) }
            }
            Picker("Refresh every", selection: $cfg.refreshSeconds) {
                ForEach(refreshOptions, id: \.self) { Text(minutesLabel($0)).tag($0) }
            }
            Toggle("Week starts on Monday", isOn: $cfg.weekStartsMonday)
            Toggle("Include pending change requests", isOn: $cfg.includePending)
            Toggle("Show year-to-date total", isOn: $cfg.enableYearTotal)
            Toggle("Count up between refreshes", isOn: $cfg.liveTick)
            Toggle("Show seconds in the menu bar while working", isOn: $cfg.barShowSecondsWhileWorking)
                .disabled(!cfg.liveTick)
            Picker("Seconds in the dropdown", selection: $cfg.dropdownSecondsScope) {
                ForEach(DropdownSecondsScope.allCases, id: \.self) { Text(label($0)).tag($0) }
            }
            .disabled(!cfg.liveTick)
        }
    }

    private var clockSection: some View {
        Section("Clock") {
            Toggle("Show clock in/out actions", isOn: $cfg.enableClockActions)
            Picker("Clock in as", selection: $cfg.defaultTelework) {
                Text("Office").tag(false)
                Text("Telework").tag(true)
            }
            .pickerStyle(.segmented)
            projectField
            Picker("\"Leave by\" clears", selection: $cfg.leaveByScope) {
                ForEach(LeaveByScope.allCases, id: \.self) { Text(label($0)).tag($0) }
            }
            Text("Which backlog the \"Leave by\" time works off: today's target alone, or the whole week/month/year deficit.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// A picker once the snapshot has loaded, a raw-id field before that.
    ///
    /// A picker whose selection matches no tag renders blank (SwiftUI's "undefined
    /// results"), hiding a configured `defaultProjectId`. So: no picker while the
    /// list is empty (first run, failed refresh), and an extra row for an id the
    /// list doesn't contain (archived project, hand-edited id).
    @ViewBuilder
    private var projectField: some View {
        if projects.isEmpty {
            TextField("Default project ID", text: projectIdText, prompt: Text("none"))
        } else {
            Picker("Default project", selection: $cfg.defaultProjectId) {
                Text("No project").tag(String?.none)
                if let id = cfg.defaultProjectId, !projects.contains(where: { $0.id == id }) {
                    Text("Project \(id) (not in the current list)").tag(String?.some(id))
                }
                ForEach(projects, id: \.id) { Text($0.name).tag(String?.some($0.id)) }
            }
        }
        Text("Changing this replaces the project last picked from \"Check in ▸\".")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var remindersSection: some View {
        Section("Reminders") {
            Toggle("Remind me to check in", isOn: $cfg.remindersEnabled)
            TextField("Windows", text: $remindersText, prompt: Text("08:00-10:00, 14:00-15:30"))
                .disabled(!cfg.remindersEnabled)
            if !invalidWindows.isEmpty {
                Text("Not a valid window: \(invalidWindows.joined(separator: ", ")). Use HH:MM-HH:MM within one day.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Picker("Remind every", selection: $cfg.reminderIntervalMinutes) {
                ForEach(reminderIntervalOptions, id: \.self) { Text(minutesLabel($0 * 60)).tag($0) }
            }
            .disabled(!cfg.remindersEnabled)
            Text("Madrid time. Only on days with hours expected and with the screen unlocked, when you haven't checked in, have checked out early, or are still on a break.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if notificationsDenied {
                Text("Notifications for Bizneo Companion are turned off in System Settings.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button("Open Notification Settings…") {
                    let id = Bundle.main.bundleIdentifier ?? ""
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .task { notificationsDenied = await ReminderNotifier.isDenied() }
    }

    private var timeOffSection: some View {
        Section("Time off") {
            TextField("Day-off schedules", text: $dayOffText, prompt: Text("Fridom, Fridom (7 hours)"))
            Text("Comma-separated schedule names that mean \"company day off\", so those days expect zero hours.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var generalSection: some View {
        Section("General") {
            // A Binding setter, not .onChange: the setter writes the real status back,
            // and .onChange would react to that write by toggling again.
            Toggle("Open at login", isOn: Binding(get: { openAtLogin }, set: setOpenAtLogin))
            if loginNeedsApproval {
                Text("Registered, but blocked in System Settings → Login Items.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button("Approve in System Settings…") { SMAppService.openSystemSettingsLoginItems() }
            }
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.red)
            }
            Text("Registers the app at its current path. For this to survive reliably, keep BizneoCompanion.app in /Applications.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var advancedSection: some View {
        Section("Advanced") {
            SecureField("Manual cookie", text: cookieText, prompt: Text("optional — bypasses Chrome"))
            Text("Set only to bypass the Chrome cookie and Keychain entirely: `_hcmex_key=…; device_id=…`.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open config file…") {
                NSWorkspace.shared.open(Config.fileURL)
            }
        }
    }

    // MARK: Bindings & options

    private var projectIdText: Binding<String> {
        Binding(get: { cfg.defaultProjectId ?? "" },
                set: { cfg.defaultProjectId = $0.isEmpty ? nil : $0 })
    }

    private var cookieText: Binding<String> {
        Binding(get: { cfg.manualCookie ?? "" },
                set: { cfg.manualCookie = $0.isEmpty ? nil : $0 })
    }

    /// Presets, plus whatever is already configured so a hand-edited interval isn't
    /// silently rounded to the nearest preset.
    private var refreshOptions: [Int] {
        Array(Set([60, 300, 600, 900, 1800, 3600] + [cfg.refreshSeconds])).sorted()
    }

    private var canSave: Bool {
        !cfg.tenant.trimmingCharacters(in: .whitespaces).isEmpty
            && !cfg.userId.trimmingCharacters(in: .whitespaces).isEmpty
            && invalidWindows.isEmpty
    }

    private var invalidWindows: [String] {
        commaList(remindersText).filter { Reminders.parseWindow($0) == nil }
    }

    private var reminderIntervalOptions: [Int] {
        Array(Set([5, 10, 15, 30, 60] + [cfg.reminderIntervalMinutes])).sorted()
    }

    /// Split on commas, trim, drop empties: the format of both list fields.
    private func commaList(_ s: String) -> [String] {
        s.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: Actions

    private func save() {
        var out = cfg
        out.tenant = out.tenant.trimmingCharacters(in: .whitespaces)
        out.userId = out.userId.trimmingCharacters(in: .whitespaces)
        out.dayOffScheduleNames = commaList(dayOffText)
        out.reminderWindows = commaList(remindersText)
        onSave(out)
    }

    /// `.requiresApproval` means registered but blocked by the user in System
    /// Settings (SMAppService.h). It counts as "on": treating it as off made the
    /// toggle unregister the very thing the user had just asked for.
    private static func loginState() -> (on: Bool, needsApproval: Bool) {
        let s = SMAppService.mainApp.status
        return (s == .enabled || s == .requiresApproval, s == .requiresApproval)
    }

    /// Shows the status macOS actually reports afterwards, never the requested one.
    private func setOpenAtLogin(_ on: Bool) {
        var failure: String?
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            failure = error.localizedDescription
        }
        let login = Self.loginState()
        openAtLogin = login.on
        loginNeedsApproval = login.needsApproval
        // register() throws "launch denied" in the approval case; the approval
        // hint above already says that better than the raw error.
        loginError = login.needsApproval ? nil : failure
    }

    // MARK: Labels

    private func label(_ m: BarMetric) -> String {
        switch m {
        case .today: return "Today"
        case .week:  return "This week"
        case .month: return "This month"
        case .year:  return "This year"
        }
    }

    private func label(_ s: DropdownSecondsScope) -> String {
        switch s {
        case .none:  return "Never"
        case .today: return "Today only"
        case .all:   return "Every row"
        }
    }

    private func label(_ s: LeaveByScope) -> String {
        switch s {
        case .none:  return "Today only"
        case .week:  return "This week's backlog"
        case .month: return "This month's backlog"
        case .year:  return "This year's backlog"
        }
    }

    private func minutesLabel(_ seconds: Int) -> String {
        guard seconds % 60 == 0 else { return "\(seconds) seconds" }
        let m = seconds / 60
        return m == 1 ? "1 minute" : "\(m) minutes"
    }
}
