import Foundation

final class MockCodexAuthReader: CodexAuthReaderProtocol, @unchecked Sendable {
    var filePath: String = "/tmp/mock-codex/auth.json"
    var stubbedState: CodexAuthState = .notInstalled
    var readCallCount = 0

    init(state: CodexAuthState = .notInstalled) {
        self.stubbedState = state
    }

    func readAuthState() -> CodexAuthState {
        readCallCount += 1
        return stubbedState
    }

    func credentialsExist() -> Bool {
        if case .notInstalled = stubbedState { return false }
        return true
    }
}
