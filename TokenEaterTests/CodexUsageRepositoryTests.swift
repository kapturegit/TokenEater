import Testing
import Foundation

@Suite("CodexUsageRepository")
struct CodexUsageRepositoryTests {

    private func makeSUT() -> (repo: CodexUsageRepository, api: MockCodexAPIClient, file: MockSharedFileService) {
        let api = MockCodexAPIClient()
        let file = MockSharedFileService()
        return (CodexUsageRepository(apiClient: api, sharedFileService: file), api, file)
    }

    /// The widget is sandboxed and has no network: everything it can ever show
    /// has to land in the shared file on the app's fetch.
    @Test("a successful fetch is written to the shared cache")
    func successWritesSharedCache() async throws {
        let (repo, api, file) = makeSUT()
        api.stubbedUsage = CodexUsageResponse(
            planType: "pro",
            rateLimit: CodexRateLimit(primaryWindow: CodexRateLimitWindow(usedPercent: 40))
        )

        let response = try await repo.refreshUsage(
            credentials: CodexCredentials(accessToken: "tok", accountId: "acct"),
            proxyConfig: nil
        )

        #expect(api.fetchCallCount == 1)
        #expect(file.updateCodexAfterSyncCallCount == 1)
        #expect(file.cachedCodexUsage?.usage.sessionWindow?.percent == 40)
        #expect(response.plan == .pro)
        // The Claude cache must be untouched: the two vendors share a file but
        // never each other's staleness.
        #expect(file.cachedUsage == nil)
    }

    @Test("credentials are forwarded to the API client")
    func forwardsCredentials() async throws {
        let (repo, api, _) = makeSUT()
        _ = try await repo.refreshUsage(
            credentials: CodexCredentials(accessToken: "tok-xyz", accountId: "acct-7"),
            proxyConfig: nil
        )
        #expect(api.lastCredentials?.accessToken == "tok-xyz")
        #expect(api.lastCredentials?.accountId == "acct-7")
    }

    /// A failed fetch must leave the previous snapshot alone rather than
    /// blanking the card.
    @Test("a failure does not touch the cache")
    func failureLeavesCacheAlone() async {
        let (repo, api, file) = makeSUT()
        api.stubbedError = APIError.httpError(statusCode: 500, endpoint: "/backend-api/wham/usage")

        do {
            _ = try await repo.refreshUsage(credentials: CodexCredentials(accessToken: "tok"), proxyConfig: nil)
            Issue.record("Expected the error to propagate")
        } catch {
            #expect(file.updateCodexAfterSyncCallCount == 0)
        }
    }
}
