import Testing
import Foundation

@MainActor
@Suite("CodexUsageStore notifications")
struct CodexStoreNotificationTests {

    private func makeSUT() -> (
        store: CodexUsageStore,
        repo: MockCodexUsageRepository,
        notifier: MockNotificationService
    ) {
        let repo = MockCodexUsageRepository()
        let notifier = MockNotificationService()
        let store = CodexUsageStore(
            repository: repo,
            authReader: MockCodexAuthReader(state: .ready(CodexCredentials(accessToken: "tok"))),
            sharedFileService: MockSharedFileService(),
            notificationService: notifier
        )
        return (store, repo, notifier)
    }

    private func toggles() -> NotificationToggles {
        NotificationToggles(
            masterEnabled: true,
            trackFiveHour: true, trackWeekly: true, trackSonnet: false, trackFable: false,
            trackCodex: true,
            sendRecovery: true, pacingHot: false, pacingWarning: false,
            resetReminderSession: false, resetReminderWeekly: false,
            resetReminderSessionOffsetMinutes: 15, resetReminderWeeklyOffsetMinutes: 60,
            extraCredits: false, tokenExpired: true,
            smartColorEnabled: false, smartColorProfile: .default,
            pacingMargin: 10, thresholds: .default,
            vendorDegraded: false, vendorRestored: false
        )
    }

    private func usage(session: Double, weekly: Double) -> CodexUsageResponse {
        CodexUsageResponse(
            planType: "plus",
            rateLimit: CodexRateLimit(
                primaryWindow: CodexRateLimitWindow(
                    usedPercent: session,
                    limitWindowSeconds: 18000,
                    resetAt: Date().addingTimeInterval(3600).timeIntervalSince1970
                ),
                secondaryWindow: CodexRateLimitWindow(
                    usedPercent: weekly,
                    limitWindowSeconds: 604800,
                    resetAt: Date().addingTimeInterval(86_400 * 3).timeIntervalSince1970
                )
            )
        )
    }

    @Test("a successful refresh evaluates Codex notifications")
    func refreshEvaluatesNotifications() async {
        let (store, repo, notifier) = makeSUT()
        store.notifTogglesProvider = { self.toggles() }
        repo.stubbedUsage = usage(session: 91, weekly: 40)
        store.isEnabled = true

        await store.refresh(force: true)

        #expect(notifier.codexEvaluationCount >= 1)
        #expect(notifier.lastCodexEvaluation?.session.pct == 91)
        #expect(notifier.lastCodexEvaluation?.weekly.pct == 40)
    }

    /// The window length has to reach the service: Smart Color weighs
    /// time-to-reset, and a 5h window judged as a 7-day one would under-alert.
    @Test("each snapshot carries its own window length")
    func snapshotsCarryWindowDuration() async throws {
        let (store, repo, notifier) = makeSUT()
        store.notifTogglesProvider = { self.toggles() }
        repo.stubbedUsage = usage(session: 50, weekly: 50)
        store.isEnabled = true

        await store.refresh(force: true)

        let evaluation = try #require(notifier.lastCodexEvaluation)
        #expect(evaluation.session.windowDuration == 18_000)
        #expect(evaluation.weekly.windowDuration == 604_800)
        #expect(evaluation.session.resetsAt != nil)
    }

    /// Loading the cache on launch must not re-announce a level the user
    /// already saw before quitting.
    @Test("loading the cache fires no notification")
    func cachedLoadIsSilent() {
        let repo = MockCodexUsageRepository()
        let notifier = MockNotificationService()
        let file = MockSharedFileService()
        file._cachedCodexUsage = CachedCodexUsage(usage: usage(session: 95, weekly: 90), fetchDate: Date())
        let store = CodexUsageStore(
            repository: repo,
            authReader: MockCodexAuthReader(state: .ready(CodexCredentials(accessToken: "tok"))),
            sharedFileService: file,
            notificationService: notifier
        )
        store.notifTogglesProvider = { self.toggles() }

        store.loadCached()

        #expect(store.sessionPct == 95)
        #expect(notifier.codexEvaluationCount == 0)
    }

    @Test("a failed refresh fires no notification")
    func failedRefreshIsSilent() async {
        let (store, repo, notifier) = makeSUT()
        store.notifTogglesProvider = { self.toggles() }
        repo.stubbedError = APIError.networkError(endpoint: "/x", underlying: "offline")
        store.isEnabled = true

        await store.refresh(force: true)

        #expect(notifier.codexEvaluationCount == 0)
    }

    /// No toggles wired (tests, or before bootstrap) must never crash or fire.
    @Test("no toggles provider means no notification")
    func noTogglesProviderIsSilent() async {
        let (store, repo, notifier) = makeSUT()
        repo.stubbedUsage = usage(session: 99, weekly: 99)
        store.isEnabled = true

        await store.refresh(force: true)

        #expect(notifier.codexEvaluationCount == 0)
    }
}
