import Testing
import Foundation

/// The widget is sandboxed and has no network: everything it renders comes
/// from the shared JSON. These cover the contract between the app's writer and
/// the widget's reader for the Codex key.
@Suite("Codex shared-file handoff")
struct CodexWidgetEntryTests {

    private func usage(session: Double, weekly: Double) -> CodexUsageResponse {
        CodexUsageResponse(
            planType: "plus",
            rateLimit: CodexRateLimit(
                primaryWindow: CodexRateLimitWindow(
                    usedPercent: session,
                    limitWindowSeconds: 18000,
                    resetAt: Date().addingTimeInterval(3600).timeIntervalSince1970
                ),
                secondaryWindow: CodexRateLimitWindow(
                    usedPercent: weekly,
                    limitWindowSeconds: 604800,
                    resetAt: Date().addingTimeInterval(86_400 * 3).timeIntervalSince1970
                )
            )
        )
    }

    /// Writing Codex must not disturb the Claude snapshot, and vice versa:
    /// both live in one file, read-modify-write.
    @Test("the two vendors' caches coexist without clobbering")
    func vendorCachesCoexist() {
        let file = MockSharedFileService()
        file.updateAfterSync(
            usage: CachedUsage(usage: .fixture(fiveHourUtil: 42), fetchDate: Date()),
            syncDate: Date()
        )
        file.updateCodexAfterSync(
            usage: CachedCodexUsage(usage: usage(session: 61, weekly: 28), fetchDate: Date()),
            syncDate: Date()
        )

        #expect(file.cachedUsage?.usage.fiveHour?.utilization == 42)
        #expect(file.cachedCodexUsage?.usage.sessionWindow?.percent == 61)
        #expect(file.cachedCodexUsage?.usage.weeklyWindow?.percent == 28)
    }

    /// nil means "the user never turned Codex on", which the widget renders as
    /// its own state rather than as an error.
    @Test("an untracked Codex leaves the key absent")
    func untrackedCodexLeavesKeyAbsent() {
        let file = MockSharedFileService()
        file.updateAfterSync(
            usage: CachedUsage(usage: .fixture(fiveHourUtil: 10), fetchDate: Date()),
            syncDate: Date()
        )
        #expect(file.cachedCodexUsage == nil)
    }

    @Test("clearing the shared file drops both vendors")
    func clearDropsBothVendors() {
        let file = MockSharedFileService()
        file.updateCodexAfterSync(
            usage: CachedCodexUsage(usage: usage(session: 61, weekly: 28), fetchDate: Date()),
            syncDate: Date()
        )
        file.clear()
        #expect(file.cachedCodexUsage == nil)
        #expect(file.cachedUsage == nil)
    }
}
