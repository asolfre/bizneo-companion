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
    /// snapshot. The hosting controller is rebuilt every time on purpose: reusing it
    /// would keep SwiftUI's `@State`, so a cancelled edit would reappear on reopen.
    func show(config: Config, projects: [ChronoProject]) {
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
    @State private var openAtLogin: Bool

    private let projects: [ChronoProject]
    private let onSave: (Config) -> Void
    private let onCancel: () -> Void

    init(config: Config,
         projects: [ChronoProject],
         onSave: @escaping (Config) -> Void,
         onCancel: @escaping () -> Void) {
        _cfg = State(initialValue: config)
        _dayOffText = State(initialValue: config.dayOffScheduleNames.joined(separator: ", "))
        _openAtLogin = State(initialValue: SMAppService.mainApp.status == .enabled)
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
    /// Without the fallback an empty project list would render an empty picker and
    /// silently wipe a configured `defaultProjectId` on the next save — the list is
    /// empty on first run and whenever a refresh has failed.
    @ViewBuilder
    private var projectField: some View {
        if projects.isEmpty {
            TextField("Default project ID", text: projectIdText, prompt: Text("none"))
        } else {
            Picker("Default project", selection: $cfg.defaultProjectId) {
                Text("No project").tag(String?.none)
                ForEach(projects, id: \.id) { Text($0.name).tag(String?.some($0.id)) }
            }
        }
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
            Toggle("Open at login", isOn: $openAtLogin)
                .onChange(of: openAtLogin) { setOpenAtLogin($0) }
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
    }

    // MARK: Actions

    private func save() {
        var out = cfg
        out.tenant = out.tenant.trimmingCharacters(in: .whitespaces)
        out.userId = out.userId.trimmingCharacters(in: .whitespaces)
        out.dayOffScheduleNames = dayOffText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        onSave(out)
    }

    /// Re-reads the real status afterwards so a failed register/unregister (an
    /// unbundled build, say) flips the toggle back instead of lying.
    private func setOpenAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSSound.beep()
        }
        openAtLogin = SMAppService.mainApp.status == .enabled
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
        let m = max(1, seconds / 60)
        return m == 1 ? "1 minute" : "\(m) minutes"
    }
}
