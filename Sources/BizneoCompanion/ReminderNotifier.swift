import Cocoa
import UserNotifications

/// macOS notifications for check-in reminders (#16).
///
/// `UNUserNotificationCenter.current()` crashes outright outside an app bundle
/// (`swift run`, `--selftest`), so every entry point checks `isAvailable` first.
/// One fixed identifier for everything posted here: a new reminder replaces the
/// previous one instead of stacking, and `withdraw()` clears it in one call.
@MainActor
final class ReminderNotifier: NSObject, UNUserNotificationCenterDelegate {
    enum Action: String {
        case checkIn, resume, notToday, openBizneo
    }

    /// Which buttons a notification carries.
    enum Kind: String {
        case checkIn   // Check in · Not today
        case resume    // Resume · Not today
        case plain     // Not today (clock actions disabled in Settings)
        case failure   // Open Bizneo · Not today
    }

    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }
    private static let identifier = "bizneo.reminder"
    private let onAction: (Action) -> Void

    init(onAction: @escaping (Action) -> Void) {
        self.onAction = onAction
        super.init()
        guard Self.isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        func button(_ a: Action, _ title: String) -> UNNotificationAction {
            UNNotificationAction(identifier: a.rawValue, title: title)
        }
        let notToday = button(.notToday, "Not today")
        let buttons: [Kind: [UNNotificationAction]] = [
            .checkIn: [button(.checkIn, "Check in"), notToday],
            .resume: [button(.resume, "Resume"), notToday],
            .plain: [notToday],
            .failure: [button(.openBizneo, "Open Bizneo"), notToday],
        ]
        center.setNotificationCategories(Set(buttons.map {
            UNNotificationCategory(identifier: $0.key.rawValue, actions: $0.value, intentIdentifiers: [])
        }))
    }

    /// Asked at launch or when reminders are switched on, never at the moment a
    /// reminder is due: that reminder would be spent on the prompt.
    func requestPermission() {
        guard Self.isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(_ kind: Kind, title: String, body: String) {
        guard Self.isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = kind.rawValue
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: Self.identifier, content: content, trigger: nil))
    }

    /// Removes the reminder from screen and Notification Center, so its buttons
    /// can't be pressed once they no longer apply.
    func withdraw() {
        guard Self.isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
    }

    /// Whether the user has turned this app's notifications off in System Settings.
    static func isDenied() async -> Bool {
        guard isAvailable else { return false }
        return await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    // Without this, macOS hides banners while the app is frontmost, which it is
    // whenever the Settings window is open.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = Action(rawValue: response.actionIdentifier)
        completionHandler()
        guard let action else { return }
        Task { @MainActor in self.onAction(action) }
    }
}
