import Foundation
import UserNotifications

final class MockNotificationCenter: NotificationCenterProtocol {
    private(set) var addedIDs: [String] = []
    /// Full requests, so tests can assert on the rendered title/body and not
    /// just on which notification fired.
    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var removedIDs: [String] = []
    var stubbedStatus: UNAuthorizationStatus = .notDetermined
    var requestAuthorizationCalled = false

    func setDelegate(_ delegate: UNUserNotificationCenterDelegate?) {}
    func requestAuthorization() { requestAuthorizationCalled = true }
    func authorizationStatus() async -> UNAuthorizationStatus { stubbedStatus }
    func add(_ request: UNNotificationRequest) {
        addedIDs.append(request.identifier)
        addedRequests.append(request)
    }

    /// Clears what was captured, for tests that assert on a second phase.
    func reset() {
        addedIDs.removeAll()
        addedRequests.removeAll()
    }
    func removePending(identifiers: [String]) { removedIDs.append(contentsOf: identifiers) }
}
