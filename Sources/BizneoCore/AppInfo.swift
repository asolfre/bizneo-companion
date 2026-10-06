import Foundation

/// Single source of truth for the app's identity and version.
///
/// `build_app.sh` scrapes `version` from this file to fill
/// `CFBundleShortVersionString` in the generated Info.plist, so the bundle can
/// never drift from the binary. Bump it here and nowhere else.
public enum AppInfo {
    public static let name = "Bizneo Companion"
    public static let version = "0.3.0"

    /// Which build this is, from the `BCBuild` key `build_app.sh` writes: `""` for a
    /// release built at its own tag, the commit (`"d8c9728"`, or `"d8c9728.dirty"`
    /// with uncommitted changes) otherwise. `nil` when not running from an app bundle.
    public static var build: String? {
        Bundle.main.object(forInfoDictionaryKey: "BCBuild") as? String
    }

    /// What to show the user: `0.3.0` for a release, `0.3.0+d8c9728` for anything
    /// else, so a development build can't be mistaken for the release it follows.
    public static var displayVersion: String { display(version: version, build: build) }

    public static func display(version: String, build: String?) -> String {
        guard let build else { return "\(version)+dev" }
        return build.isEmpty ? version : "\(version)+\(build)"
    }
}
