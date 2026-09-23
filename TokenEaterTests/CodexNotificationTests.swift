import Testing
import Foundation

@Suite("Codex notifications")
struct CodexNotificationTests {

    private func makeSUT() -> (service: NotificationService, center: MockNotificationCenter, state: MockNotificationStateStore) {
        let center = MockNotificationCenter()
        let state = MockNotificationStateStore()
        return (NotificationService(center: center, stateStore: state), center, state)
    }

    private func toggles(
        masterEnabled: Bool = true,
        trackCodex: Bool = true,
        sendRecovery: Bool = true,
        smartColor: Bool = false
    ) -> NotificationToggles {
        NotificationToggles(
            masterEnabled: masterEnabled,
            trackFiveHour: true, trackWeekly: true, trackSonnet: false, trackFable: false,
            trackCodex: trackCodex,
            sendRecovery: sendRecovery, pacingHot: false, pacingWarning: false,
            resetReminderSession: false, resetReminderWeekly: false,
            resetReminderSessionOffsetMinutes: 15, resetReminderWeeklyOffsetMinutes: 60,
            extraCredits: false, tokenExpired: true,
            smartColorEnabled: smartColor, smartColorProfile: .default,
            pacingMargin: 10, thresholds: .default,
            vendorDegraded: false, vendorRestored: false
        )
    }

    private func snapshot(_ pct: Int, resetsIn: TimeInterval, window: TimeInterval) -> MetricSnapshot {
        MetricSnapshot(
            pct: pct,
            resetsAt: Date().addingTimeInterval(resetsIn),
            windowDuration: window,
            utilization: Double(pct)
        )
    }

    private var greenSession: MetricSnapshot { snapshot(5, resetsIn: 3600, window: 5 * 3600) }
    private var greenWeekly: MetricSnapshot { snapshot(5, resetsIn: 86_400 * 3, window: 7 * 86_400) }

    // MARK: - Gating

    /// The master notification switch has to silence Codex too, or turning
    /// notifications off would still leave one vendor talking.
    @Test("the master switch silences Codex alerts")
    func masterSwitchSilencesCodex() {
        let (service, center, _) = makeSUT()
        service.evaluateCodex(
            session: snapshot(95, resetsIn: 600, window: 5 * 3600),
            weekly: greenWeekly,
            toggles: toggles(masterEnabled: false)
        )
        #expect(center.addedRequests.isEmpty)
    }

    /// Tracking Codex on the dashboard shouldn't force notifications for it.
    @Test("the Codex toggle gates Codex alerts independently")
    func codexToggleGatesAlerts() {
        let (service, center, _) = makeSUT()
        service.evaluateCodex(
            session: snapshot(95, resetsIn: 600, window: 5 * 3600),
            weekly: greenWeekly,
            toggles: toggles(trackCodex: false)
        )
        #expect(center.addedRequests.isEmpty)
    }

    // MARK: - Escalation

    @Test("crossing the critical threshold fires one Codex session alert")
    func sessionEscalationFires() {
        let (service, center, _) = makeSUT()
        service.evaluateCodex(
            session: snapshot(95, resetsIn: 600, window: 5 * 3600),
            weekly: greenWeekly,
            toggles: toggles()
        )
        #expect(center.addedRequests.count == 1)
        #expect(center.addedRequests.first?.identifier == "escalation_codexSession")
        #expect(!(center.addedRequests.first?.content.title.isEmpty ?? true))
        #expect(!(center.addedRequests.first?.content.body.isEmpty ?? true))
    }

    @Test("the weekly window fires under its own identifier")
    func weeklyEscalationFires() {
        let (service, center, _) = makeSUT()
        service.evaluateCodex(
            session: greenSession,
            weekly: snapshot(95, resetsIn: 86_400, window: 7 * 86_400),
            toggles: toggles()
        )
        #expect(center.addedRequests.map(\.identifier) == ["escalation_codexWeekly"])
    }

    /// Distinct identifiers matter: a shared one would make the two windows
    /// overwrite each other's banner in Notification Center.
    @Test("the two windows never share a notification identifier")
    func windowsUseDistinctIdentifiers() {
        let (service, center, _) = makeSUT()
        service.evaluateCodex(
            session: snapshot(95, resetsIn: 600, window: 5 * 3600),
            weekly: snapshot(95, resetsIn: 86_400, window: 7 * 86_400),
            toggles: toggles()
        )
        let ids = Set(center.addedRequests.map(\.identifier))
        #expect(ids == ["escalation_codexSession", "escalation_codexWeekly"])
    }

    /// Codex alerts must not collide with the Claude ones either.
    @Test("Codex identifiers are distinct from the Claude ones")
    func codexIdentifiersDistinctFromClaude() {
        let (service, center, _) = makeSUT()
        service.evaluateCodex(
            session: snapshot(95, resetsIn: 600, window: 5 * 3600),
            weekly: greenWeekly,
            toggles: toggles()
        )
        #expect(!center.addedRequests.map(\.identifier).contains("escalation_fiveHour"))
    }

    /// The whole point of the level bookkeeping: the same reading twice must
    /// not re-alert.
    @Test("a steady level does not re-alert")
    func steadyLevelDoesNotRealert() {
        let (service, center, _) = makeSUT()
        let hot = snapshot(95, resetsIn: 600, window: 5 * 3600)
        service.evaluateCodex(session: hot, weekly: greenWeekly, toggles: toggles())
        let afterFirst = center.addedRequests.count
        service.evaluateCodex(session: hot, weekly: greenWeekly, toggles: toggles())
        #expect(center.addedRequests.count == afterFirst)
    }

    @Test("a green reading fires nothing")
    func greenFiresNothing() {
        let (service, center, _) = makeSUT()
        service.evaluateCodex(session: greenSession, weekly: greenWeekly, toggles: toggles())
        #expect(center.addedRequests.isEmpty)
    }

    // MARK: - Recovery

    /// Recovery is gated on the window actually rolling forward, not just on
    /// the level easing back - the same #244 fix the Claude surfaces got.
    @Test("recovery fires only after the window really reset")
    func recoveryRequiresWindowReset() {
        let (service, center, _) = makeSUT()
        let reset = Date().addingTimeInterval(600)
        let hot = MetricSnapshot(pct: 95, resetsAt: reset, windowDuration: 5 * 3600, utilization: 95)
        service.evaluateCodex(session: hot, weekly: greenWeekly, toggles: toggles())
        center.reset()

        // Same window, level eased -> no "reset" claim.
        let easedSameWindow = MetricSnapshot(pct: 5, resetsAt: reset, windowDuration: 5 * 3600, utilization: 5)
        service.evaluateCodex(session: easedSameWindow, weekly: greenWeekly, toggles: toggles())
        #expect(center.addedRequests.isEmpty)
    }

    @Test("recovery fires when the window rolled forward")
    func recoveryFiresOnRealReset() {
        let (service, center, _) = makeSUT()
        let reset = Date().addingTimeInterval(600)
        let hot = MetricSnapshot(pct: 95, resetsAt: reset, windowDuration: 5 * 3600, utilization: 95)
        service.evaluateCodex(session: hot, weekly: greenWeekly, toggles: toggles())
        center.reset()

        let nextWindow = MetricSnapshot(
            pct: 2,
            resetsAt: reset.addingTimeInterval(5 * 3600),
            windowDuration: 5 * 3600,
            utilization: 2
        )
        service.evaluateCodex(session: nextWindow, weekly: greenWeekly, toggles: toggles())
        #expect(center.addedRequests.map(\.identifier) == ["recovery_codexSession"])
    }

    @Test("recovery stays silent when the user turned it off")
    func recoveryRespectsToggle() {
        let (service, center, _) = makeSUT()
        let reset = Date().addingTimeInterval(600)
        let hot = MetricSnapshot(pct: 95, resetsAt: reset, windowDuration: 5 * 3600, utilization: 95)
        service.evaluateCodex(session: hot, weekly: greenWeekly, toggles: toggles(sendRecovery: false))
        center.reset()

        let nextWindow = MetricSnapshot(
            pct: 2,
            resetsAt: reset.addingTimeInterval(5 * 3600),
            windowDuration: 5 * 3600,
            utilization: 2
        )
        service.evaluateCodex(session: nextWindow, weekly: greenWeekly, toggles: toggles(sendRecovery: false))
        #expect(center.addedRequests.isEmpty)
    }

    // MARK: - Copy
    //
    // `NSLocalizedString` resolves against `Bundle.main`, which in a test run
    // is the xctest runner, not this bundle - so asserting on a rendered
    // banner would only ever prove that the fallback path returns the key.
    // What actually matters is that every key the Codex surfaces compose at
    // runtime EXISTS in Localizable.strings: a typo there ships a banner
    // reading "notif.title.codex.weekly.red" to the user. So look the keys up
    // in this bundle directly.

    private final class BundleToken {}

    private func localized(_ key: String) -> String? {
        let bundle = Bundle(for: BundleToken.self)
        let missing = "<<missing>>"
        let value = bundle.localizedString(forKey: key, value: missing, table: nil)
        return value == missing ? nil : value
    }

    @Test("every Codex notification key exists in Localizable.strings")
    func codexCopyKeysExist() {
        var keys: [String] = [
            "settings.notifications.track.codex",
            "notif.title.codex.weekly.pace",
            "notif.body.codex.weekly.pace",
        ]
        for family in ["codex.session", "codex.weekly"] {
            for level in ["orange", "red", "green"] {
                keys.append("notif.title.\(family).\(level)")
                keys.append("notif.body.\(family).\(level)")
                keys.append("notif.body.\(family).\(level).fallback")
            }
        }
        for key in keys {
            #expect(localized(key) != nil, "missing Localizable.strings key: \(key)")
        }
    }

    /// The two windows must read differently, or a banner can't tell you which
    /// limit you just hit.
    @Test("the two windows produce distinct copy")
    func windowsProduceDistinctCopy() {
        let sessionTitle = localized("notif.title.codex.session.red")
        let weeklyTitle = localized("notif.title.codex.weekly.red")
        #expect(sessionTitle != nil)
        #expect(weeklyTitle != nil)
        #expect(sessionTitle != weeklyTitle)
    }

    /// The 5h body takes a countdown, the weekly body takes a date - both are
    /// `String(format:)`-ed with one argument, so both need exactly one `%@`.
    @Test("body formats take exactly one substitution")
    func bodyFormatsTakeOneArgument() {
        for key in [
            "notif.body.codex.session.orange",
            "notif.body.codex.session.red",
            "notif.body.codex.weekly.orange",
            "notif.body.codex.weekly.red",
            "notif.body.codex.session.green",
            "notif.body.codex.weekly.green",
        ] {
            guard let value = localized(key) else {
                Issue.record("missing key: \(key)")
                continue
            }
            #expect(value.components(separatedBy: "%@").count == 2, "\(key) should carry exactly one %@, got: \(value)")
        }
    }

    /// Fallbacks are used when there is no reset date, so they must NOT try to
    /// substitute anything.
    @Test("fallback copy carries no substitution")
    func fallbackCopyHasNoArgument() {
        for key in [
            "notif.body.codex.session.orange.fallback",
            "notif.body.codex.session.red.fallback",
            "notif.body.codex.weekly.orange.fallback",
            "notif.body.codex.weekly.red.fallback",
        ] {
            guard let value = localized(key) else {
                Issue.record("missing key: \(key)")
                continue
            }
            #expect(!value.contains("%@"), "\(key) should take no argument, got: \(value)")
        }
    }
}
