import Foundation

/// Reads the Codex CLI's ChatGPT session from `~/.codex/auth.json`.
///
/// Strictly read-only, and deliberately so. The refresh token in that file
/// rotates: if TokenEater spent it to mint a fresh access token and didn't
/// write the replacement back, the CLI's own copy would be dead the next time
/// the user ran `codex`. Breaking the user's terminal login to draw a gauge is
/// not a trade this app makes. So the app rides along on whatever access token
/// the CLI last stored (they last ~10 days, and the CLI refreshes well before
/// expiry), and when that one does lapse the UI says so instead of guessing.
///
/// Same `getpwuid` home resolution as `CredentialsFileReader`: the widget is
/// sandboxed and `FileManager.homeDirectoryForCurrentUser` would hand it the
/// container path. The widget never calls this (it reads the shared JSON), but
/// the file is compiled into all three targets, so it stays correct anyway.
final class CodexAuthReader: CodexAuthReaderProtocol, @unchecked Sendable {

    let filePath: String

    init() {
        // `CODEX_HOME` relocates the whole Codex config directory; honour it so
        // users who moved it don't silently get "not installed".
        if let override = ProcessInfo.processInfo.environment["CODEX_HOME"], !override.isEmpty {
            filePath = (override as NSString).expandingTildeInPath + "/auth.json"
            return
        }
        guard let pw = getpwuid(getuid()) else {
            filePath = ""
            return
        }
        let home = String(cString: pw.pointee.pw_dir)
        filePath = home + "/.codex/auth.json"
    }

    init(filePath: String) {
        self.filePath = filePath
    }

    func credentialsExist() -> Bool {
        FileManager.default.fileExists(atPath: filePath)
    }

    func readAuthState() -> CodexAuthState {
        guard let data = FileManager.default.contents(atPath: filePath) else {
            return .notInstalled
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unreadable
        }

        let tokens = json["tokens"] as? [String: Any]
        let accessToken = (tokens?["access_token"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        guard let accessToken else {
            // An API-key install has no `tokens` block at all, just
            // `OPENAI_API_KEY`. That's a working Codex setup with nothing to
            // track, which is a different message than a broken one.
            let apiKey = json["OPENAI_API_KEY"] as? String
            let mode = json["auth_mode"] as? String
            if (apiKey?.isEmpty == false) || mode == "apikey" {
                return .apiKeyMode
            }
            return .unreadable
        }

        let credentials = CodexCredentials(
            accessToken: accessToken,
            accountId: (tokens?["account_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? Self.accountID(fromJWT: accessToken),
            expiresAt: Self.expiry(fromJWT: accessToken)
        )

        return credentials.isExpired() ? .expired(credentials) : .ready(credentials)
    }

    // MARK: - JWT claims
    //
    // Signature is never verified here: the token is not a trust decision, it's
    // a bearer string we forward to OpenAI, who does verify it. The claims are
    // read only to answer "is this already stale" and "which account is it",
    // both of which fail safe (nil -> we just make the request).

    static func claims(fromJWT token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        guard let payload = base64URLDecode(String(parts[1])) else { return nil }
        return try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
    }

    static func expiry(fromJWT token: String) -> Date? {
        guard let exp = claims(fromJWT: token)?["exp"] as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    static func accountID(fromJWT token: String) -> String? {
        guard let auth = claims(fromJWT: token)?["https://api.openai.com/auth"] as? [String: Any] else {
            return nil
        }
        return auth["chatgpt_account_id"] as? String
    }

    private static func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}
