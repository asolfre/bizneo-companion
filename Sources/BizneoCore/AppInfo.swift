/// Single source of truth for the app's identity and version.
///
/// `build_app.sh` scrapes `version` from this file to fill `CFBundleVersion` and
/// `CFBundleShortVersionString` in the generated Info.plist, so the bundle can
/// never drift from the binary. Bump it here and nowhere else.
public enum AppInfo {
    public static let name = "Bizneo Companion"
    public static let version = "0.1.0"
}
