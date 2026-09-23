import Testing
import Foundation

@Suite("CodexUsageResponse decoding")
struct CodexUsageResponseDecodingTests {

    /// The real `backend-api/wham/usage` payload, trimmed of the keys we don't
    /// read but keeping their siblings, so the tolerant decode is exercised
    /// against the actual shape rather than a tidied-up version of it.
    private let liveShape = """
    {
      "user_id": "user-abc",
      "account_id": "acct-123",
      "email": "dev@example.com",
      "plan_type": "plus",
      "rate_limit": {
        "allowed": false,
        "limit_reached": true,
        "primary_window": {
          "used_percent": 97,
          "limit_window_seconds": 18000,
          "reset_after_seconds": 16179,
          "reset_at": 1790163473
        },
        "secondary_window": {
          "used_percent": 22,
          "limit_window_seconds": 604800,
          "reset_after_seconds": 538041,
          "reset_at": 1790685335
        }
      },
      "code_review_rate_limit": null,
      "additional_rate_limits": null,
      "model_usage": { "gpt-6-astra": { "available": false } },
      "credits": {
        "has_credits": false,
        "unlimited": false,
        "overage_limit_reached": false,
        "balance": "0"
      },
      "spend_control": { "reached": false, "individual_limit": null },
      "rate_limit_upsell": { "title": "You're out of Codex messages" }
    }
    """.data(using: .utf8)!

    @Test("decodes the live wham/usage payload")
    func decodesLivePayload() throws {
        let usage = try JSONDecoder().decode(CodexUsageResponse.self, from: liveShape)

        #expect(usage.plan == .plus)
        #expect(usage.email == "dev@example.com")
        #expect(usage.accountId == "acct-123")
        #expect(usage.sessionWindow?.percent == 97)
        #expect(usage.weeklyWindow?.percent == 22)
        #expect(usage.rateLimit?.limitReached == true)
        #expect(usage.credits?.hasCredits == false)
        #expect(usage.credits?.balance == "0")
    }

    /// The whole point of the card: how much is LEFT.
    @Test("remainingPercent is the complement of used")
    func remainingIsComplement() throws {
        let usage = try JSONDecoder().decode(CodexUsageResponse.self, from: liveShape)
        #expect(usage.sessionWindow?.remainingPercent == 3)
        #expect(usage.weeklyWindow?.remainingPercent == 78)
    }

    @Test("reset_at maps to an absolute date")
    func resetAtMapsToDate() throws {
        let usage = try JSONDecoder().decode(CodexUsageResponse.self, from: liveShape)
        #expect(usage.sessionWindow?.resetsAtDate() == Date(timeIntervalSince1970: 1790163473))
    }

    /// Some payloads carry only the relative delta; the window still has to
    /// produce a usable reset date rather than silently showing nothing.
    @Test("falls back to reset_after_seconds when reset_at is absent")
    func fallsBackToRelativeReset() {
        let window = CodexRateLimitWindow(usedPercent: 10, resetAfterSeconds: 3600)
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(window.resetsAtDate(now: now) == now.addingTimeInterval(3600))
    }

    @Test("no reset information yields no date")
    func noResetInfoYieldsNil() {
        #expect(CodexRateLimitWindow(usedPercent: 10).resetsAtDate() == nil)
    }

    /// An unfamiliar payload must never take the whole card down - that's the
    /// contract the Claude side already has, and the one that keeps a silent
    /// API change from looking like a broken app.
    @Test("unknown and missing keys decode to an empty-but-valid response")
    func tolerantDecode() throws {
        let json = """
        { "plan_type": "pro", "some_new_key": { "nested": true } }
        """.data(using: .utf8)!
        let usage = try JSONDecoder().decode(CodexUsageResponse.self, from: json)
        #expect(usage.plan == .pro)
        #expect(usage.sessionWindow == nil)
        #expect(usage.weeklyWindow == nil)
    }

    @Test("a malformed rate_limit block degrades to nil instead of failing")
    func malformedRateLimitDegrades() throws {
        let json = """
        { "plan_type": "plus", "rate_limit": "unexpected-string" }
        """.data(using: .utf8)!
        let usage = try JSONDecoder().decode(CodexUsageResponse.self, from: json)
        #expect(usage.plan == .plus)
        #expect(usage.rateLimit == nil)
    }

    @Test("credits balance decodes from a number as well as a string")
    func creditsBalanceFromNumber() throws {
        let json = """
        { "credits": { "has_credits": true, "unlimited": false, "balance": 12.5 } }
        """.data(using: .utf8)!
        let usage = try JSONDecoder().decode(CodexUsageResponse.self, from: json)
        #expect(usage.credits?.hasCredits == true)
        #expect(usage.credits?.balanceValue == 12.5)
    }

    @Test("used_percent is clamped for display")
    func percentClamped() {
        #expect(CodexRateLimitWindow(usedPercent: 140).percent == 100)
        #expect(CodexRateLimitWindow(usedPercent: -5).percent == 0)
        #expect(CodexRateLimitWindow(usedPercent: -5).remainingPercent == 100)
    }

    @Test("unrecognised plan strings fall back to unknown with no badge")
    func unknownPlan() {
        #expect(CodexPlanType(raw: "galaxy-tier") == .unknown)
        #expect(CodexPlanType(raw: nil) == .unknown)
        #expect(CodexPlanType(raw: "") == .unknown)
        #expect(CodexPlanType(raw: "PLUS") == .plus)
        #expect(CodexPlanType.unknown.displayLabel.isEmpty)
        #expect(CodexPlanType.business.displayLabel == "BUSINESS")
    }

    @Test("CachedCodexUsage round-trips through the shared JSON encoding")
    func cachedRoundTrip() throws {
        let usage = try JSONDecoder().decode(CodexUsageResponse.self, from: liveShape)
        let cached = CachedCodexUsage(usage: usage, fetchDate: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try JSONEncoder().encode(cached)
        let decoded = try JSONDecoder().decode(CachedCodexUsage.self, from: data)
        #expect(decoded.usage.sessionWindow?.percent == 97)
        #expect(decoded.usage.plan == .plus)
        #expect(decoded.fetchDate == cached.fetchDate)
    }
}
