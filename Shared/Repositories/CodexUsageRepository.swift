import Foundation

/// Codex counterpart to `UsageRepository`: one API call, then the shared JSON
/// cache the (sandboxed, network-less) widget reads from.
final class CodexUsageRepository: CodexUsageRepositoryProtocol, @unchecked Sendable {
    private let apiClient: CodexAPIClientProtocol
    private let sharedFileService: SharedFileServiceProtocol

    init(
        apiClient: CodexAPIClientProtocol = CodexAPIClient(),
        sharedFileService: SharedFileServiceProtocol = SharedFileService()
    ) {
        self.apiClient = apiClient
        self.sharedFileService = sharedFileService
    }

    func refreshUsage(credentials: CodexCredentials, proxyConfig: ProxyConfig?) async throws -> CodexUsageResponse {
        let usage = try await apiClient.fetchUsage(credentials: credentials, proxyConfig: proxyConfig)
        sharedFileService.updateCodexAfterSync(
            usage: CachedCodexUsage(usage: usage, fetchDate: Date()),
            syncDate: Date()
        )
        return usage
    }

    func testConnection(credentials: CodexCredentials, proxyConfig: ProxyConfig?) async throws -> CodexUsageResponse {
        try await apiClient.fetchUsage(credentials: credentials, proxyConfig: proxyConfig)
    }
}
