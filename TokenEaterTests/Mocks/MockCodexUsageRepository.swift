import Foundation

final class MockCodexUsageRepository: CodexUsageRepositoryProtocol, @unchecked Sendable {
    var stubbedUsage: CodexUsageResponse?
    var stubbedError: Error?
    var refreshCallCount = 0

    func refreshUsage(credentials: CodexCredentials, proxyConfig: ProxyConfig?) async throws -> CodexUsageResponse {
        refreshCallCount += 1
        if let stubbedError { throw stubbedError }
        return stubbedUsage ?? CodexUsageResponse()
    }

    func testConnection(credentials: CodexCredentials, proxyConfig: ProxyConfig?) async throws -> CodexUsageResponse {
        if let stubbedError { throw stubbedError }
        return stubbedUsage ?? CodexUsageResponse()
    }
}
