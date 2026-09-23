import Foundation

/// The ChatGPT OAuth material the Codex CLI stores on disk. Read-only: the app
/// never writes `auth.json`, so it can never invalidate the CLI's session (see
/// `CodexAuthReader`).
struct CodexCredentials: Equatable {
    let accessToken: String
    /// `tokens.account_id`. Sent as `chatgpt-account-id`; the usage endpoint
    /// also accepts the call without it, so it stays optional.
    let accountId: String?
    /// `exp` claim of the access token. nil when the JWT could not be parsed -
    /// treated as "might still be good", and the 401 path takes over.
    let expiresAt: Date?

    init(accessToken: String, accountId: String? = nil, expiresAt: Date? = nil) {
        self.accessToken = accessToken
        self.accountId = accountId
        self.expiresAt = expiresAt
    }

    /// True once the token's own `exp` has passed. Used to show the calm
    /// "run codex to refresh" state instead of firing a request we know 401s.
    func isExpired(now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return now >= expiresAt
    }
}

/// Why no usable Codex credentials were found. Drives the copy shown in the
/// dashboard card, which is the only way a user can tell "Codex isn't
/// installed" from "your login went stale".
enum CodexAuthState: Equatable {
    case ready(CodexCredentials)
    /// No `~/.codex/auth.json` at all - Codex CLI not installed, or never
    /// logged in.
    case notInstalled
    /// Signed in with an API key rather than a ChatGPT account. Usage is billed
    /// per token, so there are no plan limits to show.
    case apiKeyMode
    /// The file exists but carries no access token we can read.
    case unreadable
    /// The access token's `exp` has passed. Running Codex refreshes it.
    case expired(CodexCredentials)

    var credentials: CodexCredentials? {
        switch self {
        case .ready(let creds), .expired(let creds): return creds
        default: return nil
        }
    }
}

protocol CodexAuthReaderProtocol: Sendable {
    /// Absolute path of the credentials file, surfaced in diagnostics and
    /// watched by `TokenFileMonitor`.
    var filePath: String { get }
    func readAuthState() -> CodexAuthState
    func credentialsExist() -> Bool
}
