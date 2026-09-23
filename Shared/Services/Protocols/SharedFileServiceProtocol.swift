import Foundation

protocol SharedFileServiceProtocol: Sendable {
    var fileURL: URL { get }
    var isConfigured: Bool { get }
    var cachedUsage: CachedUsage? { get }
    var lastSyncDate: Date? { get }
    /// Last Codex snapshot. Separate from `cachedUsage` so a Codex-only or
    /// Claude-only user never has the other vendor's staleness bleed in.
    var cachedCodexUsage: CachedCodexUsage? { get }
    var codexLastSyncDate: Date? { get }
    var theme: ThemeColors { get }
    var thresholds: UsageThresholds { get }
    var smartColorEnabled: Bool { get }
    var smartColorProfile: SmartColorProfile { get }
    var pacingSchedule: PacingSchedule { get }
    var lastWeekDailyTotals: [Int]? { get }
    var lastWeekTotalsRefreshedAt: Date? { get }

    func invalidateCache()
    func updateAfterSync(usage: CachedUsage, syncDate: Date)
    func updateCodexAfterSync(usage: CachedCodexUsage, syncDate: Date)
    func updateTheme(_ theme: ThemeColors, thresholds: UsageThresholds)
    func updateSmartColorEnabled(_ enabled: Bool)
    func updateSmartColorProfile(_ profile: SmartColorProfile)
    func updatePacingSchedule(_ schedule: PacingSchedule)
    func updateLastWeekDailyTotals(_ totals: [Int], refreshedAt: Date)
    func clear()
}
