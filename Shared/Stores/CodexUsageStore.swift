import SwiftUI

/// Codex (ChatGPT) usage state - the second vendor alongside `UsageStore`.
///
/// Deliberately a sibling of `UsageStore` rather than a merge into it: the two
/// vendors have different credentials, different failure modes and different
/// refresh cadences, and a user may well track one and not the other. Keeping
/// them apart means a broken or absent Codex login can never take the Claude
/// gauges down with it.
///
/// `ObservableObject` + `@Published`, never `@Observable` - see AGENTS.md.
@MainActor
final class CodexUsageStore: ObservableObject {
    /// 5h window ("primary"), the one that interrupts work.
    @Published var sessionPct: Int = 0
    /// 7-day window ("secondary").
    @Published var weeklyPct: Int = 0
    @Published var sessionReset: String = ""
    @Published var sessionResetAbsolute: String = ""
    @Published var weeklyReset: String = ""
    @Published var weeklyResetAbsolute: String = ""
    @Published var sessionPacing: PacingResult?
    @Published var weeklyPacing: PacingResult?
    @Published var plan: CodexPlanType = .unknown
    @Published var accountEmail: String?
    @Published var credits: CodexCredits?
    /// False while the account is over one of its limits right now.
    @Published var isRateLimited: Bool = false
    @Published var lastUpdate: Date?
    @Published var isLoading = false
    @Published var errorState: AppErrorState = .none
    /// Why no credentials are usable, when that's the case. Drives the copy on
    /// the dashboard card: "Codex not installed" and "your login went stale"
    /// need different answers from the user.
    @Published private(set) var authState: CodexAuthState = .notInstalled
    @Published private(set) var lastUsage: CodexUsageResponse?
    @Published private(set) var lastAPIError: LastAPIError?

    /// Master switch from settings. When off, nothing is fetched and nothing
    /// is rendered - tracking a second vendor is opt-in.
    @Published var isEnabled: Bool = false {
        didSet {
            guard oldValue != isEnabled else { return }
            if isEnabled {
                startAutoRefresh()
                Task { await refresh(force: true) }
            } else {
                stopAutoRefresh()
            }
        }
    }

    var hasError: Bool { errorState != .none }

    /// True once we have numbers to show (live or cached).
    var hasData: Bool { lastUsage != nil }

    /// Codex is installed and logged in with a ChatGPT account, so there is
    /// something to track at all.
    var isConnectable: Bool {
        switch authState {
        case .ready, .expired: return true
        case .notInstalled, .apiKeyMode, .unreadable: return false
        }
    }

    /// The remaining half of the question the user actually asks: not "how much
    /// have I burned" but "how much do I have left".
    var sessionRemaining: Int { 100 - sessionPct }
    var weeklyRemaining: Int { 100 - weeklyPct }

    var sessionResetDate: Date? { lastUsage?.sessionWindow?.resetsAtDate() }
    var weeklyResetDate: Date? { lastUsage?.weeklyWindow?.resetsAtDate() }

    var pacingMargin: Int = 10
    var refreshIntervalSeconds: TimeInterval = 300
    var proxyConfig: ProxyConfig?

    /// Returns the current notification toggles. Wired by
    /// `StatusBarController` at bootstrap, exactly like `UsageStore`'s, so the
    /// store can fire alerts off the latest settings without holding a
    /// `SettingsStore` reference. Nil in tests -> no notifications.
    var notifTogglesProvider: (() -> NotificationToggles?)?

    private let repository: CodexUsageRepositoryProtocol
    private let authReader: CodexAuthReaderProtocol
    private let sharedFileService: SharedFileServiceProtocol
    private let notificationService: NotificationServiceProtocol
    private var autoRefreshTask: Task<Void, Never>?

    private(set) var currentSpeed: RefreshSpeed = .normal
    private(set) var retryAfterDate: Date?
    private var consecutiveRateLimits: Int = 0

    var effectiveInterval: TimeInterval {
        RateLimitBackoff.effectiveInterval(speed: currentSpeed, baseInterval: refreshIntervalSeconds)
    }

    /// Path of the credentials file, for the diagnostic report and the
    /// "where does this come from" line in settings.
    var credentialsPath: String { authReader.filePath }

    init(
        repository: CodexUsageRepositoryProtocol = CodexUsageRepository(),
        authReader: CodexAuthReaderProtocol = CodexAuthReader(),
        sharedFileService: SharedFileServiceProtocol = SharedFileService(),
        notificationService: NotificationServiceProtocol = NotificationService()
    ) {
        self.repository = repository
        self.authReader = authReader
        self.sharedFileService = sharedFileService
        self.notificationService = notificationService
    }

    // MARK: - Lifecycle

    /// Reads the cached snapshot and the auth state, without hitting the
    /// network. Called at launch so the dashboard has something on screen
    /// before the first fetch lands.
    func loadCached() {
        authState = authReader.readAuthState()
        if let cached = sharedFileService.cachedCodexUsage {
            apply(usage: cached.usage)
            lastUpdate = cached.fetchDate
        }
    }

    func reloadConfig() {
        loadCached()
        guard isEnabled else { return }
        Task { await refresh(force: true) }
    }

    func startAutoRefresh() {
        autoRefreshTask?.cancel()
        guard isEnabled else { return }
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = self.effectiveInterval
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                await self.refresh()
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    /// Called when `~/.codex/auth.json` changes on disk: the CLI just
    /// refreshed its token (or the user logged in / switched accounts), so
    /// drop the backoff and re-read immediately.
    func handleCredentialsChange() {
        retryAfterDate = nil
        consecutiveRateLimits = 0
        authState = authReader.readAuthState()
        guard isEnabled else { return }
        Task { await refresh(force: true) }
    }

    // MARK: - Refresh

    func refresh(force: Bool = false) async {
        guard isEnabled else { return }
        guard !isLoading else { return }

        authState = authReader.readAuthState()

        switch authState {
        case .notInstalled, .apiKeyMode, .unreadable:
            errorState = .tokenUnavailable
            return
        case .expired:
            // The CLI rotates its own token and we never write to its file
            // (see CodexAuthReader), so an expired token is a real dead end
            // until the user runs Codex again. Say so rather than burning a
            // request we know returns 401.
            errorState = .tokenUnavailable
            return
        case .ready(let credentials):
            await performRefresh(credentials: credentials, force: force)
        }
    }

    private func performRefresh(credentials: CodexCredentials, force: Bool) async {
        if !force, let last = lastUpdate, Date().timeIntervalSince(last) < effectiveInterval {
            return
        }
        if !force, let retryAfter = retryAfterDate, Date() < retryAfter {
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let usage = try await repository.refreshUsage(credentials: credentials, proxyConfig: proxyConfig)
            applySuccess(usage: usage)
        } catch let error as APIError {
            lastAPIError = error.diagnosticSnapshot
            switch error {
            case .tokenExpired, .noToken:
                errorState = .tokenUnavailable
            case .rateLimited(let retryAfter, _, _):
                currentSpeed = .slow
                let result = RateLimitBackoff.nextRetryDate(
                    consecutiveRateLimits: consecutiveRateLimits,
                    serverRetryAfter: retryAfter
                )
                consecutiveRateLimits = result.consecutiveRateLimits
                retryAfterDate = result.date
                errorState = .rateLimited
            default:
                errorState = .networkError
            }
        } catch {
            lastAPIError = LastAPIError(
                httpStatusCode: nil,
                retryAfterHeader: nil,
                endpoint: "(unknown)",
                timestamp: Date(),
                underlyingError: error.localizedDescription
            )
            errorState = .networkError
        }
    }

    func testConnection() async -> ConnectionTestResult {
        guard let credentials = authReader.readAuthState().credentials else {
            return ConnectionTestResult(success: false, message: String(localized: "codex.error.noCredentials"))
        }
        do {
            _ = try await repository.testConnection(credentials: credentials, proxyConfig: proxyConfig)
            return ConnectionTestResult(success: true, message: "OK")
        } catch {
            return ConnectionTestResult(success: false, message: error.localizedDescription)
        }
    }

    // MARK: - State application

    private func applySuccess(usage: CodexUsageResponse) {
        apply(usage: usage)
        errorState = .none
        lastAPIError = nil
        lastUpdate = Date()
        if currentSpeed == .slow { currentSpeed = .normal }
        retryAfterDate = nil
        consecutiveRateLimits = 0
        WidgetReloader.scheduleReload()
        evaluateNotifications(usage: usage)
    }

    /// Fires Codex threshold alerts off the fresh snapshot. Only on a real
    /// successful fetch (never on the cached-load path), so a relaunch doesn't
    /// re-announce a level the user already saw.
    private func evaluateNotifications(usage: CodexUsageResponse) {
        guard let toggles = notifTogglesProvider?() else { return }
        let session = MetricSnapshot(
            pct: sessionPct,
            resetsAt: usage.sessionWindow?.resetsAtDate(),
            windowDuration: usage.sessionWindow?.limitWindowSeconds ?? 5 * 3600,
            utilization: usage.sessionWindow?.utilization ?? Double(sessionPct)
        )
        let weekly = MetricSnapshot(
            pct: weeklyPct,
            resetsAt: usage.weeklyWindow?.resetsAtDate(),
            windowDuration: usage.weeklyWindow?.limitWindowSeconds ?? 7 * 86_400,
            utilization: usage.weeklyWindow?.utilization ?? Double(weeklyPct)
        )
        notificationService.evaluateCodex(session: session, weekly: weekly, toggles: toggles)
    }

    func apply(usage: CodexUsageResponse) {
        lastUsage = usage
        sessionPct = usage.sessionWindow?.percent ?? 0
        weeklyPct = usage.weeklyWindow?.percent ?? 0
        plan = usage.plan
        accountEmail = usage.email
        credits = usage.credits
        isRateLimited = usage.rateLimit?.limitReached ?? false
        refreshResetCountdown()
        recalculatePacing()
    }

    func refreshResetCountdown() {
        let session = ResetCountdownFormatter.session(from: sessionResetDate)
        sessionReset = session.relative
        sessionResetAbsolute = session.absolute
        let weekly = ResetCountdownFormatter.weekly(from: weeklyResetDate)
        weeklyReset = weekly.relative
        weeklyResetAbsolute = weekly.absolute
    }

    /// Codex windows are plain rolling windows (5h / 7d), so they pace exactly
    /// like Claude's. The workweek schedule is deliberately NOT applied here:
    /// it is a Claude-side preference about *your* week, and silently
    /// reinterpreting a second vendor's quota through it would make the two
    /// numbers incomparable.
    func recalculatePacing() {
        guard let usage = lastUsage else {
            sessionPacing = nil
            weeklyPacing = nil
            return
        }
        sessionPacing = PacingCalculator.calculate(
            utilization: usage.sessionWindow?.utilization ?? 0,
            resetsAt: usage.sessionWindow?.resetsAtDate(),
            bucket: .fiveHour,
            margin: Double(pacingMargin)
        )
        weeklyPacing = PacingCalculator.calculate(
            utilization: usage.weeklyWindow?.utilization ?? 0,
            resetsAt: usage.weeklyWindow?.resetsAtDate(),
            bucket: .sevenDay,
            margin: Double(pacingMargin)
        )
    }
}
