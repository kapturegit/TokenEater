import Foundation

final class MockCodexAPIClient: CodexAPIClientProtocol, @unchecked Sendable {
    var stubbedUsage: CodexUsageResponse?
    var stubbedError: Error?
    var fetchCallCount = 0
    var lastCredentials: CodexCredentials?

    func fetchUsage(credentials: CodexCredentials, proxyConfig: ProxyConfig?) async throws -> CodexUsageResponse {
        fetchCallCount += 1
        lastCredentials = credentials
        if let stubbedError { throw stubbedError }
        return stubbedUsage ?? CodexUsageResponse()
    }

    func testConnection(credentials: CodexCredentials, proxyConfig: ProxyConfig?) async -> ConnectionTestResult {
        if stubbedError != nil { return ConnectionTestResult(success: false, message: "fail") }
        return ConnectionTestResult(success: true, message: "OK")
    }
}
