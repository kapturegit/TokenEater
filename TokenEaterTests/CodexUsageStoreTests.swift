import Testing
import Foundation

@MainActor
@Suite("CodexUsageStore")
struct CodexUsageStoreTests {

    // MARK: - Helpers

    private func makeSUT(
        authState: CodexAuthState = .ready(CodexCredentials(accessToken: "tok", accountId: "acct"))
    ) -> (store: CodexUsageStore, repo: MockCodexUsageRepository, auth: MockCodexAuthReader, file: MockSharedFileService) {
        let repo = MockCodexUsageRepository()
        let auth = MockCodexAuthReader(state: authState)
        let file = MockSharedFileService()
        // Always a mock notifier: the live one builds
        // `UNUserNotificationCenter.current()` eagerly, which aborts in a test
        // bundle that has no host app.
        let store = CodexUsageStore(
            repository: repo,
            authReader: auth,
            sharedFileService: file,
            notificationService: MockNotificationService()
        )
        return (store, repo, auth, file)
    }

    private func usage(session: Double, weekly: Double, plan: String = "plus") -> CodexUsageResponse {
        CodexUsageResponse(
            planType: plan,
            email: "dev@example.com",
            accountId: "acct",
            rateLimit: CodexRateLimit(
                allowed: true,
                limitReached: false,
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
            ),
            credits: CodexCredits(hasCredits: false, unlimited: false, balance: "0")
        )
    }

    // MARK: - Opt-in gate

    /// Tracking a second vendor is opt-in: a disabled store must not reach the
    /// network, or a user who never asked for Codex would still be making
    /// requests to OpenAI on their behalf.
    @Test("a disabled store never fetches")
    func disabledStoreNeverFetches() async {
        let (store, repo, _, _) = makeSUT()
        store.isEnabled = false

        await store.refresh(force: true)

        #expect(repo.refreshCallCount == 0)
        #expect(store.hasData == false)
    }

    @Test("enabling fetches and publishes both windows")
    func enabledStorePublishesWindows() async {
        let (store, repo, _, _) = makeSUT()
        repo.stubbedUsage = usage(session: 97, weekly: 22)
        store.isEnabled = true

        await store.refresh(force: true)

        #expect(repo.refreshCallCount >= 1)
        #expect(store.sessionPct == 97)
        #expect(store.weeklyPct == 22)
        #expect(store.sessionRemaining == 3)
        #expect(store.weeklyRemaining == 78)
        #expect(store.plan == .plus)
        #expect(store.accountEmail == "dev@example.com")
        #expect(store.errorState == .none)
        #expect(store.hasData)
    }

    @Test("reset countdowns are populated from the windows")
    func resetCountdownsPopulated() async {
        let (store, repo, _, _) = makeSUT()
        repo.stubbedUsage = usage(session: 10, weekly: 5)
        store.isEnabled = true

        await store.refresh(force: true)

        #expect(!store.sessionReset.isEmpty)
        #expect(!store.weeklyReset.isEmpty)
        #expect(store.sessionResetDate != nil)
        #expect(store.weeklyResetDate != nil)
    }

    // MARK: - Auth states

    /// An expired token can't be refreshed without writing to the CLI's file,
    /// which the app refuses to do - so it must not burn a request it knows
    /// returns 401.
    @Test("an expired login is reported without hitting the network")
    func expiredLoginSkipsNetwork() async {
        let creds = CodexCredentials(accessToken: "tok", expiresAt: Date().addingTimeInterval(-60))
        let (store, repo, _, _) = makeSUT(authState: .expired(creds))
        store.isEnabled = true

        await store.refresh(force: true)

        #expect(repo.refreshCallCount == 0)
        #expect(store.errorState == .tokenUnavailable)
    }

    @Test("a missing Codex install is reported without hitting the network")
    func notInstalledSkipsNetwork() async {
        let (store, repo, _, _) = makeSUT(authState: .notInstalled)
        store.isEnabled = true

        await store.refresh(force: true)

        #expect(repo.refreshCallCount == 0)
        #expect(store.errorState == .tokenUnavailable)
        #expect(store.isConnectable == false)
    }

    @Test("an API-key install is not connectable")
    func apiKeyModeNotConnectable() async {
        let (store, _, _, _) = makeSUT(authState: .apiKeyMode)
        store.isEnabled = true

        await store.refresh(force: true)

        #expect(store.isConnectable == false)
        #expect(store.authState == .apiKeyMode)
    }

    // MARK: - Errors

    @Test("a 401 surfaces as an unavailable token")
    func unauthorizedSurfacesTokenUnavailable() async {
        let (store, repo, _, _) = makeSUT()
        repo.stubbedError = APIError.tokenExpired(endpoint: "/backend-api/wham/usage", statusCode: 401)
        store.isEnabled = true

        await store.refresh(force: true)

        #expect(store.errorState == .tokenUnavailable)
        #expect(store.lastAPIError?.httpStatusCode == 401)
    }

    @Test("a 429 backs off and marks the store rate limited")
    func rateLimitedBacksOff() async {
        let (store, repo, _, _) = makeSUT()
        repo.stubbedError = APIError.rateLimited(retryAfter: 120, retryAfterRaw: "120", endpoint: "/backend-api/wham/usage")
        store.isEnabled = true

        await store.refresh(force: true)

        #expect(store.errorState == .rateLimited)
        #expect(store.retryAfterDate != nil)
    }

    @Test("a transport failure surfaces as a network error")
    func networkErrorSurfaces() async {
        let (store, repo, _, _) = makeSUT()
        repo.stubbedError = APIError.networkError(endpoint: "/backend-api/wham/usage", underlying: "offline")
        store.isEnabled = true

        await store.refresh(force: true)

        #expect(store.errorState == .networkError)
    }

    /// A successful fetch after a failure must clear every error field, or the
    /// card keeps showing a warning next to fresh numbers.
    @Test("a success clears a prior error")
    func successClearsPriorError() async {
        let (store, repo, _, _) = makeSUT()
        store.isEnabled = true
        repo.stubbedError = APIError.networkError(endpoint: "/x", underlying: "offline")
        await store.refresh(force: true)
        #expect(store.errorState == .networkError)

        repo.stubbedError = nil
        repo.stubbedUsage = usage(session: 12, weekly: 4)
        await store.refresh(force: true)

        #expect(store.errorState == .none)
        #expect(store.lastAPIError == nil)
        #expect(store.sessionPct == 12)
    }

    // MARK: - Cache

    @Test("loadCached shows the last snapshot without a fetch")
    func loadCachedShowsSnapshot() {
        let (store, repo, _, file) = makeSUT()
        file._cachedCodexUsage = CachedCodexUsage(
            usage: usage(session: 55, weekly: 33),
            fetchDate: Date(timeIntervalSince1970: 1_700_000_000)
        )

        store.loadCached()

        #expect(repo.refreshCallCount == 0)
        #expect(store.sessionPct == 55)
        #expect(store.weeklyPct == 33)
        #expect(store.lastUpdate == Date(timeIntervalSince1970: 1_700_000_000))
    }

    // MARK: - Pacing

    /// Codex windows are plain rolling windows, so they must pace through the
    /// same calculator as Claude's - a Codex 5h at 50% halfway through its
    /// window is "on track" exactly like a Claude one.
    @Test("pacing is computed for both windows")
    func pacingComputed() async {
        let (store, repo, _, _) = makeSUT()
        repo.stubbedUsage = usage(session: 50, weekly: 50)
        store.isEnabled = true

        await store.refresh(force: true)

        #expect(store.sessionPacing != nil)
        #expect(store.weeklyPacing != nil)
    }

    @Test("pacing is cleared when there is no snapshot")
    func pacingClearedWithoutData() {
        let (store, _, _, _) = makeSUT()
        store.recalculatePacing()
        #expect(store.sessionPacing == nil)
        #expect(store.weeklyPacing == nil)
    }
}
