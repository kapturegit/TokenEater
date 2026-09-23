import Foundation
import Combine

protocol TokenFileMonitorProtocol {
    func startMonitoring()
    func stopMonitoring()
    var tokenChanged: AnyPublisher<Void, Never> { get }
    /// Fires when `~/.codex/auth.json` changes: the Codex CLI refreshed its
    /// access token, or the user logged in / switched ChatGPT accounts. Kept
    /// separate from `tokenChanged` so a Codex event never forces a Claude
    /// refresh (and vice versa) - the two vendors rate-limit independently.
    var codexCredentialsChanged: AnyPublisher<Void, Never> { get }
}
