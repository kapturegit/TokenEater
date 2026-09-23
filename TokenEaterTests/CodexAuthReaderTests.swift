import Testing
import Foundation

@Suite("CodexAuthReader")
struct CodexAuthReaderTests {

    // MARK: - Helpers

    /// Builds an unsigned JWT with the given payload. `CodexAuthReader` never
    /// verifies the signature (OpenAI does), so a fake one is exactly what the
    /// production path sees minus the cryptography.
    private func makeJWT(claims: [String: Any]) -> String {
        let header = Data(#"{"alg":"RS256","typ":"JWT"}"#.utf8)
        let payload = try! JSONSerialization.data(withJSONObject: claims)
        func b64(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return "\(b64(header)).\(b64(payload)).fake-signature"
    }

    private func writeAuthFile(_ json: String) -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-auth-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("auth.json").path
        try? json.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    private func chatGPTAuthFile(exp: TimeInterval, accountId: String? = "acct-123") -> String {
        var claims: [String: Any] = ["exp": exp]
        claims["https://api.openai.com/auth"] = ["chatgpt_account_id": "acct-from-jwt"]
        let token = makeJWT(claims: claims)
        let accountLine = accountId.map { "\"account_id\": \"\($0)\"," } ?? ""
        return """
        {
          "auth_mode": "chatgpt",
          "OPENAI_API_KEY": null,
          "tokens": { \(accountLine) "access_token": "\(token)", "refresh_token": "rt.1.abc" },
          "last_refresh": "2026-09-15T04:10:52Z"
        }
        """
    }

    // MARK: - States

    @Test("a live ChatGPT login reads as ready")
    func readsReadyCredentials() {
        let future = Date().addingTimeInterval(86_400).timeIntervalSince1970
        let reader = CodexAuthReader(filePath: writeAuthFile(chatGPTAuthFile(exp: future)))

        guard case .ready(let credentials) = reader.readAuthState() else {
            Issue.record("Expected .ready")
            return
        }
        #expect(credentials.accountId == "acct-123")
        #expect(!credentials.accessToken.isEmpty)
        #expect(credentials.isExpired() == false)
    }

    /// The CLI's file has carried the account id inconsistently across
    /// versions; the JWT always has it, so it's the fallback.
    @Test("account id falls back to the JWT claim")
    func accountIdFallsBackToJWT() {
        let future = Date().addingTimeInterval(86_400).timeIntervalSince1970
        let reader = CodexAuthReader(filePath: writeAuthFile(chatGPTAuthFile(exp: future, accountId: nil)))

        #expect(reader.readAuthState().credentials?.accountId == "acct-from-jwt")
    }

    /// An expired token is reported as such rather than fired at the API: we
    /// can't refresh it without writing to the CLI's file, so the UI has to
    /// tell the user to run Codex.
    @Test("a lapsed token reads as expired, not ready")
    func readsExpiredCredentials() {
        let past = Date().addingTimeInterval(-3600).timeIntervalSince1970
        let reader = CodexAuthReader(filePath: writeAuthFile(chatGPTAuthFile(exp: past)))

        guard case .expired(let credentials) = reader.readAuthState() else {
            Issue.record("Expected .expired")
            return
        }
        #expect(credentials.isExpired())
    }

    @Test("a missing file reads as not installed")
    func missingFileIsNotInstalled() {
        let reader = CodexAuthReader(filePath: "/tmp/definitely-not-here-\(UUID().uuidString)/auth.json")
        #expect(reader.readAuthState() == .notInstalled)
        #expect(reader.credentialsExist() == false)
    }

    /// An API-key install is a working Codex with nothing to track - a
    /// different message from a broken login.
    @Test("an API-key install is distinguished from a broken one")
    func apiKeyModeIsItsOwnState() {
        let path = writeAuthFile("""
        { "auth_mode": "apikey", "OPENAI_API_KEY": "sk-proj-abc", "tokens": null }
        """)
        #expect(CodexAuthReader(filePath: path).readAuthState() == .apiKeyMode)
    }

    @Test("a token-less chatgpt file reads as unreadable")
    func tokenlessFileIsUnreadable() {
        let path = writeAuthFile("""
        { "auth_mode": "chatgpt", "OPENAI_API_KEY": null, "tokens": { "refresh_token": "rt.1.abc" } }
        """)
        #expect(CodexAuthReader(filePath: path).readAuthState() == .unreadable)
    }

    @Test("malformed JSON reads as unreadable rather than crashing")
    func malformedJSONIsUnreadable() {
        let path = writeAuthFile("{ not json at all")
        #expect(CodexAuthReader(filePath: path).readAuthState() == .unreadable)
    }

    /// A token whose JWT we can't parse must not be treated as expired - that
    /// would hide working credentials behind a "run codex" message.
    @Test("an unparseable token is used rather than assumed stale")
    func unparseableTokenIsStillUsed() {
        let path = writeAuthFile("""
        { "auth_mode": "chatgpt", "tokens": { "access_token": "not-a-jwt", "account_id": "acct-9" } }
        """)
        guard case .ready(let credentials) = CodexAuthReader(filePath: path).readAuthState() else {
            Issue.record("Expected .ready")
            return
        }
        #expect(credentials.expiresAt == nil)
        #expect(credentials.isExpired() == false)
    }

    @Test("expiry is read from the JWT exp claim")
    func expiryFromJWT() {
        let exp: TimeInterval = 1_790_309_452
        let token = makeJWT(claims: ["exp": exp])
        #expect(CodexAuthReader.expiry(fromJWT: token) == Date(timeIntervalSince1970: exp))
        #expect(CodexAuthReader.expiry(fromJWT: "garbage") == nil)
    }
}
