import Foundation
import Security

/// Mirrors the clock state into Slack's status and presence (#13).
/// See `docs/plans/done/slack-status-sync.md`.
public enum SlackStatus {
    /// What to show in Slack. Empty `text`/`emoji` = clear the status.
    public struct Target: Equatable {
        public let text: String
        public let emoji: String
        /// `users.setPresence` only accepts `auto` or `away`.
        public let presence: String
        public var clears: Bool { text.isEmpty }
    }

    public static let working = Target(text: "Working", emoji: ":computer:", presence: "auto")
    public static let onBreak = Target(text: "On a break", emoji: ":coffee:", presence: "away")
    public static let off = Target(text: "", emoji: "", presence: "away")
    /// Sent once when the sync is switched off: drop our status, hand presence back.
    public static let disabled = Target(text: "", emoji: "", presence: "auto")

    /// nil = send nothing: the state is unknown, so don't guess.
    public static func target(for state: BarState) -> Target? {
        switch state {
        case .working: return working
        case .onBreak: return onBreak
        case .notCheckedIn, .checkedOutEarly, .doneForToday, .offDuty: return off
        case .unknown: return nil
        }
    }

    /// Whether a status currently in Slack may be replaced: empty, or one we set.
    /// Anything else was set by hand (vacation, meeting) and is left alone.
    public static func isOwned(text: String, emoji: String) -> Bool {
        (text.isEmpty && emoji.isEmpty)
            || [working, onBreak].contains { $0.text == text && $0.emoji == emoji }
    }

    public enum PushResult: Equatable { case applied, skippedManualStatus }

    /// Read the current status, then set status + presence if it's ours to change.
    /// Needs a user token with `users.profile:read`, `users.profile:write`, `users:write`.
    public static func push(_ t: Target, token: String, expiresAt: Date) async throws -> PushResult {
        let current = try await call("users.profile.get", token: token, json: nil)
        let profile = current["profile"] as? [String: Any] ?? [:]
        guard isOwned(text: profile["status_text"] as? String ?? "",
                      emoji: profile["status_emoji"] as? String ?? "") else {
            return .skippedManualStatus
        }
        _ = try await call("users.profile.set", token: token, json: ["profile": [
            "status_text": t.text,
            "status_emoji": t.emoji,
            "status_expiration": t.clears ? 0 : Int(expiresAt.timeIntervalSince1970),
        ]])
        _ = try await call("users.setPresence", token: token, json: ["presence": t.presence])
        return .applied
    }

    public struct APIError: Error, LocalizedError {
        public let method: String
        public let message: String
        public var errorDescription: String? { "Slack \(method): \(message)" }
    }

    /// Slack answers HTTP 200 with `"ok": false` on errors, so `ok` is what counts.
    private static func call(_ method: String, token: String, json: [String: Any]?) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: "https://slack.com/api/\(method)")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let json {
            req.httpMethod = "POST"
            req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        let (data, _) = try await URLSession.shared.data(for: req)
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard obj["ok"] as? Bool == true else {
            throw APIError(method: method, message: obj["error"] as? String ?? "unreadable response")
        }
        return obj
    }
}

/// The Slack user token, kept in the login Keychain rather than `config.json`.
public enum SlackToken {
    private static let base: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "BizneoCompanion.Slack",
        kSecAttrAccount as String: "user-token",
    ]

    public static func read() -> String? {
        var q = base
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let s = String(data: data, encoding: .utf8), !s.isEmpty
        else { return nil }
        return s
    }

    /// Empty token = delete.
    @discardableResult
    public static func save(_ token: String) -> Bool {
        guard !token.isEmpty else { return delete() }
        let data = Data(token.utf8)
        let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = base
            q[kSecValueData as String] = data
            return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    @discardableResult
    public static func delete() -> Bool {
        let s = SecItemDelete(base as CFDictionary)
        return s == errSecSuccess || s == errSecItemNotFound
    }
}
