import Foundation

// MARK: - API Response
//
// Shape of `GET https://chatgpt.com/backend-api/wham/usage`, the endpoint the
// Codex CLI itself reads its `/status` limits from. Every field is optional:
// OpenAI adds and retires keys there without notice (`code_review_rate_limit`,
// `model_usage`, the upsell blob...), and an unfamiliar payload must never
// break the decode of the two windows we actually display.

struct CodexUsageResponse: Codable, Equatable {
    /// Raw plan string ("free", "plus", "pro", "business"...). Mapped through
    /// `CodexPlanType` for display.
    let planType: String?
    /// Account e-mail, shown so a user with several ChatGPT accounts can tell
    /// which one the numbers belong to.
    let email: String?
    let accountId: String?
    let rateLimit: CodexRateLimit?
    let credits: CodexCredits?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case email
        case accountId = "account_id"
        case rateLimit = "rate_limit"
        case credits
    }

    init(
        planType: String? = nil,
        email: String? = nil,
        accountId: String? = nil,
        rateLimit: CodexRateLimit? = nil,
        credits: CodexCredits? = nil
    ) {
        self.planType = planType
        self.email = email
        self.accountId = accountId
        self.rateLimit = rateLimit
        self.credits = credits
    }

    /// Decode tolerantly, mirroring `UsageResponse`: unknown keys are ignored
    /// and a broken sub-object becomes nil instead of failing the whole parse.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        planType = try? container.decode(String.self, forKey: .planType)
        email = try? container.decode(String.self, forKey: .email)
        accountId = try? container.decode(String.self, forKey: .accountId)
        rateLimit = try? container.decode(CodexRateLimit.self, forKey: .rateLimit)
        credits = try? container.decode(CodexCredits.self, forKey: .credits)
    }

    var plan: CodexPlanType { CodexPlanType(raw: planType) }

    /// The 5h rolling window ("primary" in OpenAI's vocabulary), the one that
    /// actually stops you mid-task. Maps to Claude's 5h session bucket.
    var sessionWindow: CodexRateLimitWindow? { rateLimit?.primaryWindow }

    /// The weekly window ("secondary"), maps to Claude's 7-day bucket.
    var weeklyWindow: CodexRateLimitWindow? { rateLimit?.secondaryWindow }
}

struct CodexRateLimit: Codable, Equatable {
    /// False once the account is over a limit right now.
    let allowed: Bool?
    let limitReached: Bool?
    let primaryWindow: CodexRateLimitWindow?
    let secondaryWindow: CodexRateLimitWindow?

    enum CodingKeys: String, CodingKey {
        case allowed
        case limitReached = "limit_reached"
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }

    init(
        allowed: Bool? = nil,
        limitReached: Bool? = nil,
        primaryWindow: CodexRateLimitWindow? = nil,
        secondaryWindow: CodexRateLimitWindow? = nil
    ) {
        self.allowed = allowed
        self.limitReached = limitReached
        self.primaryWindow = primaryWindow
        self.secondaryWindow = secondaryWindow
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        allowed = try? container.decode(Bool.self, forKey: .allowed)
        limitReached = try? container.decode(Bool.self, forKey: .limitReached)
        primaryWindow = try? container.decode(CodexRateLimitWindow.self, forKey: .primaryWindow)
        secondaryWindow = try? container.decode(CodexRateLimitWindow.self, forKey: .secondaryWindow)
    }
}

/// One rolling quota window. The Claude side of the app speaks in
/// `utilization` + an ISO-8601 `resets_at`; OpenAI ships a whole-number
/// `used_percent` + a Unix `reset_at`, so this type exposes both shapes and
/// the rest of the app never has to know which vendor it came from.
struct CodexRateLimitWindow: Codable, Equatable {
    /// 0...100, how much of the window is consumed.
    let usedPercent: Double
    /// Length of the window in seconds (18000 = 5h, 604800 = 7d). Feeds
    /// `GaugeColorResolver` so Smart Color paces Codex exactly like Claude.
    let limitWindowSeconds: TimeInterval?
    /// Seconds until the window refills, as computed server-side.
    let resetAfterSeconds: TimeInterval?
    /// Unix epoch of the refill.
    let resetAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAfterSeconds = "reset_after_seconds"
        case resetAt = "reset_at"
    }

    init(
        usedPercent: Double,
        limitWindowSeconds: TimeInterval? = nil,
        resetAfterSeconds: TimeInterval? = nil,
        resetAt: TimeInterval? = nil
    ) {
        self.usedPercent = usedPercent
        self.limitWindowSeconds = limitWindowSeconds
        self.resetAfterSeconds = resetAfterSeconds
        self.resetAt = resetAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercent = (try? container.decode(Double.self, forKey: .usedPercent)) ?? 0
        limitWindowSeconds = try? container.decode(TimeInterval.self, forKey: .limitWindowSeconds)
        resetAfterSeconds = try? container.decode(TimeInterval.self, forKey: .resetAfterSeconds)
        resetAt = try? container.decode(TimeInterval.self, forKey: .resetAt)
    }

    /// Same name/meaning as `UsageBucket.utilization`, so shared helpers
    /// (pacing, Smart Color) take either vendor's window unchanged.
    var utilization: Double { usedPercent }

    /// Prefers the absolute `reset_at`; falls back to `reset_after_seconds`
    /// measured from `now` for the rare payload that only carries the delta.
    /// The fallback is relative to the call, so callers that cache the
    /// response should re-read it rather than storing the resulting Date.
    func resetsAtDate(now: Date = Date()) -> Date? {
        if let resetAt, resetAt > 0 { return Date(timeIntervalSince1970: resetAt) }
        if let resetAfterSeconds { return now.addingTimeInterval(resetAfterSeconds) }
        return nil
    }

    /// Whole-number used percentage, clamped to 0...100 for display.
    var percent: Int { Int(min(max(usedPercent, 0), 100).rounded()) }

    /// How much of the window is left - the "how much do I have left" half of
    /// the question, rendered next to the used percentage.
    var remainingPercent: Int { 100 - percent }
}

/// Codex credit balance. `balance` arrives as a string ("0", "12.50") but has
/// also been seen as a number, so it is decoded from either.
struct CodexCredits: Codable, Equatable {
    let hasCredits: Bool
    let unlimited: Bool
    let overageLimitReached: Bool
    let balance: String?

    enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited
        case overageLimitReached = "overage_limit_reached"
        case balance
    }

    init(hasCredits: Bool = false, unlimited: Bool = false, overageLimitReached: Bool = false, balance: String? = nil) {
        self.hasCredits = hasCredits
        self.unlimited = unlimited
        self.overageLimitReached = overageLimitReached
        self.balance = balance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasCredits = (try? container.decode(Bool.self, forKey: .hasCredits)) ?? false
        unlimited = (try? container.decode(Bool.self, forKey: .unlimited)) ?? false
        overageLimitReached = (try? container.decode(Bool.self, forKey: .overageLimitReached)) ?? false
        if let string = try? container.decode(String.self, forKey: .balance) {
            balance = string
        } else if let number = try? container.decode(Double.self, forKey: .balance) {
            balance = String(number)
        } else {
            balance = nil
        }
    }

    /// Numeric balance when it parses, for "0 credits" style gating.
    var balanceValue: Double? { balance.flatMap(Double.init) }
}

// MARK: - Plan

/// ChatGPT plan behind a Codex account. The raw strings come straight from
/// `plan_type`; anything unrecognised falls back to `.unknown` and the badge
/// simply doesn't render (same contract as `PlanType` on the Claude side).
enum CodexPlanType: String, Codable, CaseIterable {
    case free
    case plus
    case pro
    case team
    case business
    case enterprise
    case edu
    case unknown

    init(raw: String?) {
        guard let raw = raw?.lowercased(), !raw.isEmpty else {
            self = .unknown
            return
        }
        self = CodexPlanType(rawValue: raw) ?? .unknown
    }

    var displayLabel: String {
        switch self {
        case .unknown: return ""
        default: return rawValue.uppercased()
        }
    }
}

// MARK: - Cached usage (offline + widget)

struct CachedCodexUsage: Codable, Equatable {
    let usage: CodexUsageResponse
    let fetchDate: Date
}
