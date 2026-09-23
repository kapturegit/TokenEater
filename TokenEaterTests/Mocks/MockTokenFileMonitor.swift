import Foundation
import Combine

final class MockTokenFileMonitor: TokenFileMonitorProtocol {
    private let subject = PassthroughSubject<Void, Never>()
    private let codexSubject = PassthroughSubject<Void, Never>()
    var startCallCount = 0
    var stopCallCount = 0

    var tokenChanged: AnyPublisher<Void, Never> { subject.eraseToAnyPublisher() }
    var codexCredentialsChanged: AnyPublisher<Void, Never> { codexSubject.eraseToAnyPublisher() }

    func startMonitoring() { startCallCount += 1 }
    func stopMonitoring() { stopCallCount += 1 }

    func simulateTokenChange() { subject.send(()) }
    func simulateCodexCredentialsChange() { codexSubject.send(()) }
}
