import Foundation

/// Talks to the one Codex endpoint TokenEater uses.
///
/// `GET https://chatgpt.com/backend-api/wham/usage` is the same call the Codex
/// CLI's `/status` makes: it returns the account's plan, the 5h ("primary") and
/// weekly ("secondary") rate-limit windows, and the credit balance. Read-only,
/// and the only network call the Codex side of the app makes - nothing is ever
/// sent to OpenAI beyond the bearer token the CLI already stored locally.
///
/// Errors reuse `APIError` so `CodexUsageStore` gets the same 401 / 429 /
/// transport handling (and the same diagnostic report) as the Claude side.
final class CodexAPIClient: CodexAPIClientProtocol, @unchecked Sendable {
    private let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    /// Honest identification rather than impersonating `codex_cli_rs`: the
    /// endpoint accepts any agent, so there is nothing to gain from pretending
    /// to be the CLI, and a recognisable string means OpenAI can tell this
    /// traffic apart if they ever care to.
    private let userAgent: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        return "TokenEater/\(version)"
    }()

    private func session(proxyConfig: ProxyConfig?) -> URLSession {
        guard let proxy = proxyConfig, proxy.isValidForUse else { return .shared }
        let c = URLSessionConfiguration.default
        c.connectionProxyDictionary = [
            kCFNetworkProxiesSOCKSEnable as String: true,
            kCFNetworkProxiesSOCKSProxy as String: proxy.host,
            kCFNetworkProxiesSOCKSPort as String: proxy.port,
        ]
        return URLSession(configuration: c)
    }

    private func makeRequest(credentials: CodexCredentials) -> URLRequest {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        // Optional: the endpoint resolves the account from the token when the
        // header is absent, but sending it keeps multi-account logins honest.
        if let accountId = credentials.accountId {
            request.setValue(accountId, forHTTPHeaderField: "chatgpt-account-id")
        }
        return request
    }

    func fetchUsage(credentials: CodexCredentials, proxyConfig: ProxyConfig?) async throws -> CodexUsageResponse {
        let request = makeRequest(credentials: credentials)
        let endpoint = usageURL.path
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session(proxyConfig: proxyConfig).data(for: request)
        } catch {
            throw APIError.networkError(endpoint: endpoint, underlying: error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(endpoint: endpoint)
        }

        switch httpResponse.statusCode {
        case 200:
            guard let usage = try? JSONDecoder().decode(CodexUsageResponse.self, from: data) else {
                throw APIError.invalidResponse(endpoint: endpoint)
            }
            return usage
        case 401, 403:
            throw APIError.tokenExpired(endpoint: endpoint, statusCode: httpResponse.statusCode)
        case 429:
            let retryAfterRaw = httpResponse.value(forHTTPHeaderField: "Retry-After")
            let retryAfter = retryAfterRaw.flatMap(TimeInterval.init)
            throw APIError.rateLimited(retryAfter: retryAfter, retryAfterRaw: retryAfterRaw, endpoint: endpoint)
        default:
            throw APIError.httpError(statusCode: httpResponse.statusCode, endpoint: endpoint)
        }
    }

    func testConnection(credentials: CodexCredentials, proxyConfig: ProxyConfig?) async -> ConnectionTestResult {
        do {
            let usage = try await fetchUsage(credentials: credentials, proxyConfig: proxyConfig)
            let pct = usage.sessionWindow?.percent ?? 0
            return ConnectionTestResult(success: true, message: String(format: String(localized: "test.success"), pct))
        } catch let error as APIError {
            switch error {
            case .tokenExpired(_, let statusCode):
                return ConnectionTestResult(success: false, message: String(format: String(localized: "test.expired"), statusCode))
            case .rateLimited:
                return ConnectionTestResult(success: true, message: String(localized: "test.ratelimited"))
            case .httpError(let statusCode, _):
                return ConnectionTestResult(success: false, message: String(format: String(localized: "test.http"), statusCode))
            default:
                return ConnectionTestResult(success: false, message: error.localizedDescription)
            }
        } catch {
            return ConnectionTestResult(success: false, message: String(format: String(localized: "error.network"), error.localizedDescription))
        }
    }
}
