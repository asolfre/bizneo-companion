import Foundation

/// Parsers for the Bizneo time-tracking HTML fragments.
/// All selectors are anchored on stable labels/classes observed in the live HTML.
public enum TimesheetParser {

    private static func firstMatch(_ pattern: String, in text: String, group: Int = 1) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, options: [], range: range),
              m.numberOfRanges > group else { return nil }
        let g = m.range(at: group)
        guard g.location != NSNotFound, let r = Range(g, in: text) else { return nil }
        return String(text[r])
    }

    /// True if `pattern` matches anywhere in `text` (no capture group needed).
    private static func hasMatch(_ pattern: String, in text: String) -> Bool {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return re.firstMatch(in: text, options: [], range: range) != nil
    }

    private static func stripTags(_ html: String) -> String {
        let noTags = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return noTags.replacingOccurrences(of: "&nbsp;", with: " ")
                     .replacingOccurrences(of: "&amp;", with: "&")
                     .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                     .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - hub_chrono (today)

    /// Parse `/chrono/{id}/hub_chrono`. Returns today's scheduled & logged minutes.
    /// Source text looks like: "... Total scheduled 8:00 Logged 7:31 Missing 0:28 ...".
    public static func parseHubChrono(_ html: String) -> (scheduledMin: Int, loggedMin: Int)? {
        let text = stripTags(html)
        guard let schedStr = firstMatch(#"Total scheduled\s*([0-9]{1,3}:[0-9]{2})"#, in: text),
              let scheduled = TimeFmt.parseHM(schedStr) else { return nil }
        // "Logged" appears after the scheduled total in the summary block.
        let loggedStr = firstMatch(#"Total scheduled\s*[0-9]{1,3}:[0-9]{2}\s*Logged\s*([0-9]{1,3}:[0-9]{2})"#, in: text)
            ?? firstMatch(#"([0-9]{1,3}:[0-9]{2})\s*logged today"#, in: text)
        guard let lStr = loggedStr, let logged = TimeFmt.parseHM(lStr) else { return nil }
        return (scheduled, logged)
    }

    // MARK: - my-logs header (month)

    /// Parse the month "Balance / Until today" KPI (signed minutes, negative = behind).
    /// Source: `<span ...> -14h 21m </span> <span ...> Until today </span>`.
    public static func parseMonthBalance(_ html: String) -> Int? {
        guard let raw = firstMatch(#"([+-]?\s*\d+h\s*\d+m)\s*</span>\s*<span[^>]*>\s*Until today"#, in: html)
            ?? firstMatch(#"([+-]?\s*\d+h\s*\d+m)[^<]*</[^>]+>\s*<[^>]*>\s*Until today"#, in: html) else {
            // Fallback: stripped-text proximity.
            let text = stripTags(html)
            if let s = firstMatch(#"([+-]?\d+h\s*\d+m)\s*Until today"#, in: text) {
                return TimeFmt.parseHhMm(s)
            }
            return nil
        }
        return TimeFmt.parseHhMm(raw.replacingOccurrences(of: " ", with: ""))
    }

    /// Parse the month total "Logged" (e.g. "93h 39m"). Best-effort, for display only.
    public static func parseMonthLogged(_ html: String) -> Int? {
        if let s = firstMatch(#"font-semibold shrink-0">\s*(\d+h\s*\d+m)"#, in: html) {
            return TimeFmt.parseHhMm(s)
        }
        let text = stripTags(html)
        if let s = firstMatch(#"(\d+h\s*\d+m)\s+[+-]?\d+h\s*\d+m\s*Until today"#, in: text) {
            return TimeFmt.parseHhMm(s)
        }
        if let s = firstMatch(#"Logged\s*([0-9]+h\s*[0-9]+m)"#, in: text) { return TimeFmt.parseHhMm(s) }
        return nil
    }

    // MARK: - my-logs day rows

    /// Parse every day row from the my-logs page.
    public static func parseDays(_ html: String) -> [DayLog] {
        // Split on the day-row anchor so each chunk is one day.
        let anchor = #"data-bulk-element=["'](\d{4}-\d{2}-\d{2})["']"#
        guard let re = try? NSRegularExpression(pattern: anchor) else { return [] }
        let ns = NSRange(html.startIndex..., in: html)
        let matches = re.matches(in: html, range: ns)
        guard !matches.isEmpty else { return [] }

        var days: [DayLog] = []
        for (i, m) in matches.enumerated() {
            guard let fullRange = Range(m.range, in: html),
                  let dateR = Range(m.range(at: 1), in: html) else { continue }
            let date = String(html[dateR])
            // Row chunk = from this anchor to the start of the next day row (or +4000 chars).
            let startIdx = fullRange.lowerBound
            let endIdx: String.Index
            if i + 1 < matches.count, let nextRange = Range(matches[i + 1].range, in: html) {
                endIdx = nextRange.lowerBound
            } else {
                endIdx = html.index(startIdx, offsetBy: 4000, limitedBy: html.endIndex) ?? html.endIndex
            }
            let chunk = String(html[startIdx..<endIdx])

            var day = DayLog(dateString: date)

            // Balance: the signed value inside the is-(positive|negative)-balance tag.
            if let bal = firstMatch(#"is-(?:positive|negative)-balance[^>]*>\s*<p[^>]*>\s*([+-]?\d{1,3}:\d{2})"#, in: chunk)
                ?? firstMatch(#"is-(?:positive|negative)-balance[^>]*>\s*([+-]?\d{1,3}:\d{2})"#, in: chunk) {
                day.balanceMin = TimeFmt.parseHM(bal)
            }

            // Pending change-request id ("View request" → /logged-time-requests/{digits}).
            if let rid = firstMatch(#"logged-time-requests/(\d+)"#, in: chunk) {
                day.pendingRequestId = rid
            }

            // Expected range and current logged total via the stripped column text.
            // The chunk starts mid-<tr> (at the data-bulk-element attribute), so drop
            // everything up to the first '>' (the tr tag close) before stripping tags.
            let body: Substring
            if let gt = chunk.firstIndex(of: ">") {
                body = chunk[chunk.index(after: gt)...]
            } else {
                body = Substring(chunk)
            }
            let text = stripTags(String(body))
            // Schedule name = label between the "DD Weekday" prefix and the expected range,
            // e.g. "15 Mon Mon-Thu 08:00-16:00…" → "Mon-Thu"; "5 Fri Fridom 08:00-14:00…" → "Fridom".
            if let name = firstMatch(#"\d{1,2}\s+\S{2,3}\s+(.+?)\s+\d{1,2}:\d{2}\s*-\s*\d{1,2}:\d{2}"#, in: text) {
                day.scheduleName = name.trimmingCharacters(in: .whitespaces)
            }
            if let exp = firstMatch(#"(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})"#, in: text, group: 0) {
                let comps = exp.replacingOccurrences(of: " ", with: "").components(separatedBy: "-")
                if comps.count == 2, let mins = TimeFmt.rangeMinutes(comps[0], comps[1]) {
                    day.expectedMin = mins
                }
            }
            // Current logged total = balance + expected (most robust given column ambiguity).
            if let b = day.balanceMin, let e = day.expectedMin {
                day.loggedMin = b + e
            }
            days.append(day)
        }
        return days
    }

    // MARK: - request detail (pending proposed duration)

    /// Parse a `/time-attendance/logged-time-requests/{id}` fragment.
    /// Looks for an explicit "Duration H:MM"; falls back to summing HH:MM-HH:MM ranges.
    public static func parseRequestDetail(_ html: String) -> (proposedMin: Int?, state: String?) {
        let text = stripTags(html)
        var proposed: Int?
        if let d = firstMatch(#"Duration[:\s]*([0-9]{1,3}:[0-9]{2})"#, in: text) {
            proposed = TimeFmt.parseHM(d)
        } else {
            // Sum all clock ranges that are not zero-length breaks.
            guard let re = try? NSRegularExpression(pattern: #"(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})"#) else {
                return (nil, nil)
            }
            let ns = NSRange(text.startIndex..., in: text)
            var total = 0
            var found = false
            for m in re.matches(in: text, range: ns) {
                guard let r1 = Range(m.range(at: 1), in: text), let r2 = Range(m.range(at: 2), in: text) else { continue }
                if let mins = TimeFmt.rangeMinutes(String(text[r1]), String(text[r2])), mins > 0 {
                    total += mins; found = true
                }
            }
            if found { proposed = total }
        }
        var state: String?
        for s in ["pending", "approved", "rejected"] where text.lowercased().contains(s) { state = s; break }
        return (proposed, state)
    }

    // MARK: - chronometer state (clock in/out)

    /// Parse a `#chronometer-wrapper` fragment (from hub_chrono or a clock action
    /// response) into the current clock state.
    public static func parseChronoState(_ html: String) -> ChronoState {
        let csrf = firstMatch(#"name="_csrf_token"[^>]*\bvalue="([^"]*)""#, in: html)
        let shift = firstMatch(#"name="shift_id"[^>]*\bvalue="([^"]*)""#, in: html)
        let chronoId = firstMatch(#"name="pause"[^>]*\bvalue="([^"]*)""#, in: html)
            ?? firstMatch(#"value="([^"]*)"[^>]*name="pause""#, in: html)
        let formId = firstMatch(#"<form[^>]*\bid="([^"]*)""#, in: html)
        let startedAt = firstMatch(#"data-from="([^"]*)""#, in: html)

        // State signals:
        //  • stopped → the start form posts to the collection: hx-post="/chrono" + user_id input
        //  • working → a hidden kind input pre-armed to "rest" (the Break button)
        //  • paused  → has a pause button but kind is a radio (working_time/telework)
        let isStopped = html.contains(#"hx-post="/chrono""#)
            || (firstMatch(#"name="user_id"[^>]*\bvalue="([^"]*)""#, in: html) != nil && startedAt == nil)
        let hiddenKindRest = hasMatch(#"name="kind"[^>]*type="hidden"[^>]*value="rest""#, in: html)
            || hasMatch(#"type="hidden"[^>]*name="kind"[^>]*value="rest""#, in: html)
            || hasMatch(#"name="kind"[^>]*value="rest"[^>]*type="hidden""#, in: html)

        let status: ChronoStatus
        if isStopped {
            status = .stopped
        } else if hiddenKindRest {
            status = .working
        } else if chronoId != nil {
            status = .paused
        } else {
            status = .unknown
        }

        // Project options from the projects[] select.
        var projects: [ChronoProject] = []
        if let sel = firstMatch(#"<select[^>]*name="projects\[\]"[^>]*>(.*?)</select>"#, in: html),
           let re = try? NSRegularExpression(pattern: #"<option[^>]*value="([^"]*)"[^>]*>(.*?)</option>"#,
                                             options: [.dotMatchesLineSeparators]) {
            let ns = NSRange(sel.startIndex..., in: sel)
            for m in re.matches(in: sel, range: ns) {
                guard let rv = Range(m.range(at: 1), in: sel), let rn = Range(m.range(at: 2), in: sel) else { continue }
                let id = String(sel[rv])
                if id.isEmpty { continue }
                let name = stripTags(String(sel[rn]))
                projects.append(ChronoProject(id: id, name: name))
            }
        }

        return ChronoState(status: status, chronoId: chronoId, shiftId: shift,
                           csrfToken: csrf, formId: formId, startedAt: startedAt, projects: projects)
    }
}
