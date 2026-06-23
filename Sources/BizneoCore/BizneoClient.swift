import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// HTTP client for Bizneo's internal time-tracking fragments, authenticated with the
/// reused Chrome session cookie.
public final class BizneoClient {
    private let config: Config
    private let session: URLSession
    private var cachedCookie: String?

    public init(config: Config) {
        self.config = config
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpShouldSetCookies = false
        cfg.httpCookieAcceptPolicy = .never
        cfg.timeoutIntervalForRequest = 25
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: cfg)
    }

    private func cookieHeader() throws -> String {
        if let manual = config.manualCookie, !manual.isEmpty { return manual }
        if let cached = cachedCookie { return cached }
        let header = try ChromeCookies.cookieHeader(profile: config.chromeProfile, host: config.host)
        cachedCookie = header
        return header
    }

    /// Force re-reading the cookie on next request (e.g. after a 401).
    public func invalidateCookie() { cachedCookie = nil }

    private func get(_ path: String) async throws -> String {
        guard let url = URL(string: "https://\(config.host)\(path)") else {
            throw BizneoError.network("Bad URL \(path)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(try cookieHeader(), forHTTPHeaderField: "Cookie")
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.setValue("https://\(config.host)/", forHTTPHeaderField: "Referer")
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36",
                     forHTTPHeaderField: "User-Agent")
        return try await perform(req)
    }

    /// Send an `application/x-www-form-urlencoded` mutating request (POST/PUT) that
    /// mirrors the htmx chronometer form, returning the `#chronometer-wrapper` fragment.
    private func sendChronoForm(method: String, path: String, body: String,
                                csrf: String?, formId: String?) async throws -> String {
        guard let url = URL(string: "https://\(config.host)\(path)") else {
            throw BizneoError.network("Bad URL \(path)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body.data(using: .utf8)
        req.setValue(try cookieHeader(), forHTTPHeaderField: "Cookie")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        if let csrf { req.setValue(csrf, forHTTPHeaderField: "X-CSRF-Token") }
        req.setValue("true", forHTTPHeaderField: "HX-Request")
        req.setValue("chronometer-wrapper", forHTTPHeaderField: "HX-Target")
        if let formId { req.setValue(formId, forHTTPHeaderField: "HX-Trigger") }
        req.setValue("https://\(config.host)/", forHTTPHeaderField: "HX-Current-URL")
        req.setValue("true", forHTTPHeaderField: "X-No-Layout")
        req.setValue("https://\(config.host)", forHTTPHeaderField: "Origin")
        req.setValue("https://\(config.host)/", forHTTPHeaderField: "Referer")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36",
                     forHTTPHeaderField: "User-Agent")
        return try await perform(req)
    }

    private func perform(_ req: URLRequest) async throws -> String {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw BizneoError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw BizneoError.network("No HTTP response")
        }
        // A redirect to the login/welcome page (or 401/403) means the session is dead.
        let finalPath = http.url?.path ?? ""
        if http.statusCode == 401 || http.statusCode == 403
            || finalPath.contains("/welcome") || finalPath.contains("/users/sign_in") {
            throw BizneoError.notAuthenticated
        }
        guard (200..<300).contains(http.statusCode) else {
            throw BizneoError.http(http.statusCode, finalPath)
        }
        let html = String(decoding: data, as: UTF8.self)
        if html.contains("id=\"new_user\"") || html.contains("Sign in to your account") {
            throw BizneoError.notAuthenticated
        }
        return html
    }

    // MARK: - Endpoints

    public func fetchHubChrono() async throws -> String {
        try await get("/chrono/\(config.userId)/hub_chrono")
    }

    public func fetchMonthLogs(month: Int, year: Int) async throws -> String {
        try await get("/time-attendance/my-logs/\(config.userId)?month=\(month)&year=\(year)")
    }

    public func fetchRequestDetail(id: String) async throws -> String {
        try await get("/time-attendance/logged-time-requests/\(id)")
    }

    // MARK: - High-level refresh

    /// Fetch everything and assemble a snapshot for `now`.
    public func refresh(now: Date = Date()) async throws -> Snapshot {
        let cal = Calculator.madridCalendar(weekStartsMonday: config.weekStartsMonday)
        let month = cal.component(.month, from: now)
        let year = cal.component(.year, from: now)

        async let hubHTML = fetchHubChrono()
        async let monthHTML = fetchMonthLogs(month: month, year: year)
        let hub = try await hubHTML
        let logs = try await monthHTML

        let hubChrono = TimesheetParser.parseHubChrono(hub)
        let chronoState = TimesheetParser.parseChronoState(hub)
        let monthBalance = TimesheetParser.parseMonthBalance(logs)
        let monthLogged = TimesheetParser.parseMonthLogged(logs)
        let days = TimesheetParser.parseDays(logs)

        // Resolve pending change-requests → proposed durations (current month).
        let pending = await resolvePending(in: days)

        var snapshot = Calculator.makeSnapshot(
            config: config,
            hubChrono: hubChrono,
            monthBalanceMin: monthBalance,
            monthLoggedMin: monthLogged,
            days: days,
            pending: pending,
            now: now)
        snapshot.chrono = chronoState

        // Year-to-date = cached past months (Jan..prev) + current month (live).
        if config.enableYearTotal {
            snapshot.year = try await computeYear(currentMonth: month, year: year, current: snapshot.month)
        }
        return snapshot
    }

    /// Resolve pending change-requests in a set of day rows into proposed durations.
    private func resolvePending(in days: [DayLog]) async -> [PendingRequest] {
        guard config.includePending else { return [] }
        var pending: [PendingRequest] = []
        for d in days where d.pendingRequestId != nil {
            guard let id = d.pendingRequestId else { continue }
            var req = PendingRequest(id: id, dateString: d.dateString, currentLoggedMin: d.loggedMin)
            if let detail = try? await fetchRequestDetail(id: id) {
                let parsed = TimesheetParser.parseRequestDetail(detail)
                req.proposedMin = parsed.proposedMin
                req.state = parsed.state
            }
            pending.append(req)
        }
        return pending
    }

    // MARK: - Year-to-date (cached)

    private struct MonthTotal { var balanceMin: Int; var pendingDeltaMin: Int }
    private var yearCache: [Int: MonthTotal] = [:]   // key: month 1..12 of `yearCacheYear`
    private var yearCacheYear = 0
    private var yearCacheStamp = Date.distantPast
    private let yearCacheTTL: TimeInterval = 3 * 3600

    private func computeMonthTotal(month: Int, year: Int) async throws -> MonthTotal {
        let html = try await fetchMonthLogs(month: month, year: year)
        let days = TimesheetParser.parseDays(html)
        let balance = Calculator.dayOffCorrectedSum(days: days, dayOffNames: config.dayOffScheduleNames)
        let pending = await resolvePending(in: days)
        let delta = pending.reduce(0) { $0 + $1.deltaMin }
        return MonthTotal(balanceMin: balance, pendingDeltaMin: delta)
    }

    private func computeYear(currentMonth: Int, year: Int, current: PeriodStat) async throws -> PeriodStat {
        // Invalidate cache on year rollover or TTL expiry.
        if yearCacheYear != year || Date().timeIntervalSince(yearCacheStamp) > yearCacheTTL {
            yearCache.removeAll()
            yearCacheYear = year
            yearCacheStamp = Date()
        }
        var pastBalance = 0
        var pastPending = 0
        if currentMonth > 1 {
            for m in 1..<currentMonth {
                if yearCache[m] == nil {
                    yearCache[m] = (try? await computeMonthTotal(month: m, year: year))
                        ?? MonthTotal(balanceMin: 0, pendingDeltaMin: 0)
                }
                pastBalance += yearCache[m]?.balanceMin ?? 0
                pastPending += yearCache[m]?.pendingDeltaMin ?? 0
            }
        }
        var stat = PeriodStat(label: "This year")
        stat.officialBalanceMin = pastBalance + current.officialBalanceMin
        stat.pendingDeltaMin = pastPending + current.pendingDeltaMin
        return stat
    }

    // MARK: - Chronometer (clock in/out)

    /// Fetch the current clock state from the hub_chrono widget.
    public func fetchChronoState() async throws -> ChronoState {
        TimesheetParser.parseChronoState(try await fetchHubChrono())
    }

    private func urlEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    /// Perform a clock action. Re-reads the current state first (for a fresh CSRF
    /// token, shift id and chrono id), then issues the exact request the web app sends.
    /// Returns the resulting clock state.
    @discardableResult
    public func performChrono(_ action: ChronoAction) async throws -> ChronoState {
        let state = try await fetchChronoState()
        let csrf = state.csrfToken ?? ""
        let shift = state.shiftId ?? ""
        let uid = config.userId
        let formId = state.formId
        func field(_ n: String, _ v: String) -> String { "\(urlEncode(n))=\(urlEncode(v))" }

        let html: String
        switch action {
        case .checkIn(let projectIds, let telework):
            // POST /chrono (collection): start a new chronometer.
            var parts = [field("_csrf_token", csrf), field("location_id", ""),
                         field("user_id", uid)]
            for pid in projectIds { parts.append("projects%5B%5D=\(urlEncode(pid))") }
            parts.append(field("shift_id", shift))
            parts.append(field("kind", telework ? "telework" : "working_time"))
            html = try await sendChronoForm(method: "POST", path: "/chrono",
                                            body: parts.joined(separator: "&"),
                                            csrf: csrf, formId: formId)
        case .takeBreak:
            // PUT /chrono/{uid} with pause + kind=rest.
            let body = [field("_method", "put"), field("_csrf_token", csrf),
                        field("location_id", ""), field("shift_id", shift),
                        field("kind", "rest"), field("comment", ""),
                        field("pause", state.chronoId ?? "")].joined(separator: "&")
            html = try await sendChronoForm(method: "PUT", path: "/chrono/\(uid)",
                                            body: body, csrf: csrf, formId: formId)
        case .resume:
            // PUT /chrono/{uid} with pause + kind=working_time|telework (per config).
            let body = [field("_method", "put"), field("_csrf_token", csrf),
                        field("location_id", ""), field("shift_id", shift),
                        field("kind", config.defaultTelework ? "telework" : "working_time"),
                        field("comment", ""),
                        field("pause", state.chronoId ?? "")].joined(separator: "&")
            html = try await sendChronoForm(method: "PUT", path: "/chrono/\(uid)",
                                            body: body, csrf: csrf, formId: formId)
        case .checkOut:
            // PUT /chrono/{uid} WITHOUT pause → stops the chronometer.
            let body = [field("_method", "put"), field("_csrf_token", csrf),
                        field("location_id", ""), field("shift_id", shift),
                        field("kind", "working_time"), field("comment", "")].joined(separator: "&")
            html = try await sendChronoForm(method: "PUT", path: "/chrono/\(uid)",
                                            body: body, csrf: csrf, formId: formId)
        }
        return TimesheetParser.parseChronoState(html)
    }
}
