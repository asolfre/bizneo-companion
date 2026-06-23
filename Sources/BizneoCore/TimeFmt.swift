import Foundation

/// Time helpers. All durations are represented as signed integer **minutes**.
/// Negative balance = behind schedule; positive = ahead.
public enum TimeFmt {

    /// Parse strings like `8:00`, `+0:35`, `-2:43`, `0:28` → minutes (signed).
    public static func parseHM(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let m = t.range(of: #"^([+-]?)(\d{1,3}):(\d{2})$"#, options: .regularExpression) else { return nil }
        let str = String(t[m])
        let sign = str.hasPrefix("-") ? -1 : 1
        let body = str.replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "-", with: "")
        let parts = body.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let mm = Int(parts[1]) else { return nil }
        return sign * (h * 60 + mm)
    }

    /// Parse strings like `93h 39m`, `-14h 21m`, `8h`, `0h` → minutes (signed).
    public static func parseHhMm(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let m = t.range(of: #"^([+-]?)\s*(\d+)h(?:\s*(\d+)m)?$"#, options: .regularExpression) else { return nil }
        let str = String(t[m]).replacingOccurrences(of: " ", with: "")
        let sign = str.hasPrefix("-") ? -1 : 1
        let clean = str.replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "-", with: "")
        let hPart = clean.components(separatedBy: "h")
        guard let h = Int(hPart[0]) else { return nil }
        var mm = 0
        if hPart.count > 1 {
            let mStr = hPart[1].replacingOccurrences(of: "m", with: "")
            mm = Int(mStr) ?? 0
        }
        return sign * (h * 60 + mm)
    }

    /// Compute minutes between two `HH:MM` clock times (end - start), same day.
    public static func rangeMinutes(_ start: String, _ end: String) -> Int? {
        guard let a = parseHM(start), let b = parseHM(end) else { return nil }
        return b - a
    }

    /// Format signed minutes as `+H:MM` / `-H:MM` (e.g. -163 → "-2:43", 14 → "+0:14").
    public static func signed(_ minutes: Int) -> String {
        let sign = minutes < 0 ? "-" : "+"
        let a = abs(minutes)
        return String(format: "%@%d:%02d", sign, a / 60, a % 60)
    }

    /// Format unsigned minutes as `H:MM` (e.g. 480 → "8:00").
    public static func plain(_ minutes: Int) -> String {
        let a = abs(minutes)
        return String(format: "%d:%02d", a / 60, a % 60)
    }
}
