import WidgetKit
import Foundation

struct UsageEntry: TimelineEntry {
    let date: Date
    let usage: UsageResponse?
    let error: String?
    let isStale: Bool
    let lastSync: Date?
    /// 7 daily token totals (oldest first). Only populated for the
    /// History Sparkline widget. Refreshed by the main app once a day.
    let lastWeekDailyTotals: [Int]?
    /// Codex (ChatGPT) snapshot, when the user turned the second vendor on.
    /// nil means "not tracked" rather than "no data", which the Codex widget
    /// renders as its own explicit state.
    let codexUsage: CodexUsageResponse?

    init(
        date: Date,
        usage: UsageResponse?,
        error: String? = nil,
        isStale: Bool = false,
        lastSync: Date? = nil,
        lastWeekDailyTotals: [Int]? = nil,
        codexUsage: CodexUsageResponse? = nil
    ) {
        self.date = date
        self.usage = usage
        self.error = error
        self.isStale = isStale
        self.lastSync = lastSync
        self.lastWeekDailyTotals = lastWeekDailyTotals
        self.codexUsage = codexUsage
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func iso8601String(from date: Date) -> String {
        iso8601Formatter.string(from: date)
    }

    static var placeholder: UsageEntry {
        UsageEntry(
            date: Date(),
            usage: UsageResponse(
                fiveHour: UsageBucket(utilization: 35, resetsAt: iso8601String(from: Date().addingTimeInterval(3600))),
                sevenDay: UsageBucket(utilization: 52, resetsAt: iso8601String(from: Date().addingTimeInterval(86400 * 3))),
                sevenDaySonnet: UsageBucket(utilization: 12, resetsAt: iso8601String(from: Date().addingTimeInterval(86400 * 3)))
            ),
            lastWeekDailyTotals: [120_000, 180_000, 95_000, 240_000, 310_000, 150_000, 220_000],
            codexUsage: CodexUsageResponse(
                planType: "plus",
                rateLimit: CodexRateLimit(
                    primaryWindow: CodexRateLimitWindow(
                        usedPercent: 61,
                        limitWindowSeconds: 18000,
                        resetAt: Date().addingTimeInterval(4200).timeIntervalSince1970
                    ),
                    secondaryWindow: CodexRateLimitWindow(
                        usedPercent: 28,
                        limitWindowSeconds: 604800,
                        resetAt: Date().addingTimeInterval(86400 * 4).timeIntervalSince1970
                    )
                )
            )
        )
    }

    static var unconfigured: UsageEntry {
        UsageEntry(date: Date(), usage: nil, error: String(localized: "error.notoken"))
    }
}
