import Testing
import Foundation
import AppKit

@Suite("Codex menu bar + popover segments")
struct CodexMenuBarSegmentTests {

    private func data(
        segments: [MenuBarSegment],
        hasCodex: Bool,
        codexSessionPct: Int = 40,
        codexWeeklyPct: Int = 12
    ) -> MenuBarRenderer.RenderData {
        MenuBarRenderer.RenderData(
            composition: MenuBarComposition(segments: segments),
            fiveHourPct: 10,
            sevenDayPct: 5,
            sonnetPct: 0,
            weeklyPacingDelta: 0,
            weeklyPacingZone: .onTrack,
            hasWeeklyPacing: false,
            sessionPacingDelta: 0,
            sessionPacingZone: .onTrack,
            hasSessionPacing: false,
            fablePacingDelta: 0,
            fablePacingZone: .onTrack,
            hasFablePacing: false,
            hasConfig: true,
            hasError: false,
            isAwaitingRefresh: false,
            themeColors: .default,
            thresholds: .default,
            menuBarMonochrome: false,
            fiveHourReset: "1h30",
            fiveHourResetAbsolute: "20:30",
            fiveHourResetDate: Date().addingTimeInterval(5400),
            sevenDayResetDate: Date().addingTimeInterval(86_400),
            sonnetResetDate: nil,
            hasFiveHourBucket: true,
            resetTextColorHex: "#FFFFFF",
            sessionPeriodColorHex: "#888888",
            smartResetColor: false,
            smartColorProfile: .default,
            pacingMargin: 10,
            fablePct: 0,
            hasFable: false,
            fableResetDate: nil,
            outageActive: false,
            outageHealth: .healthy,
            nextPollSeconds: nil,
            extraCreditsPct: 0,
            hasExtraCredits: false,
            codexSessionPct: codexSessionPct,
            codexWeeklyPct: codexWeeklyPct,
            codexSessionResetDate: Date().addingTimeInterval(3600),
            codexWeeklyResetDate: Date().addingTimeInterval(86_400 * 3),
            hasCodex: hasCodex
        )
    }

    /// A pinned Codex segment must widen the item when the data exists and
    /// vanish when it doesn't - the same presence gating Fable and Extra
    /// Credits use, so an enabled-but-unconfigured Codex never shows 0%.
    @Test("Codex segments render when present and disappear when absent")
    func codexSegmentPresenceGating() {
        let segments = [
            MenuBarSegment(kind: .session, style: .labelValue),
            MenuBarSegment(kind: .codexSession, style: .labelValue),
        ]
        let withCodex = MenuBarRenderer.renderUncached(data(segments: segments, hasCodex: true))
        let withoutCodex = MenuBarRenderer.renderUncached(data(segments: segments, hasCodex: false))

        #expect(withCodex.size.width > withoutCodex.size.width)
    }

    /// Both vendors pinned at once is the whole point of the feature; the two
    /// must not collapse into one another.
    @Test("both vendors can be pinned side by side")
    func bothVendorsPinned() {
        let claudeOnly = MenuBarRenderer.renderUncached(
            data(segments: [MenuBarSegment(kind: .session, style: .labelValue)], hasCodex: true)
        )
        let both = MenuBarRenderer.renderUncached(
            data(segments: [
                MenuBarSegment(kind: .session, style: .labelValue),
                MenuBarSegment(kind: .codexSession, style: .labelValue),
                MenuBarSegment(kind: .codexWeekly, style: .labelValue),
            ], hasCodex: true)
        )
        #expect(both.size.width > claudeOnly.size.width)
    }

    /// Two segments labelled "5h" would be unreadable, so Codex carries its
    /// own prefix.
    @Test("Codex labels are distinct from the Claude ones")
    func codexLabelsAreDistinct() {
        #expect(MenuBarSegmentKind.codexSession.isCodex)
        #expect(MenuBarSegmentKind.codexWeekly.isCodex)
        #expect(!MenuBarSegmentKind.session.isCodex)
        #expect(MenuBarSegmentKind.codexSession.isPresenceGated)
        #expect(MenuBarSegmentKind.codexWeekly.isPresenceGated)
    }

    @Test("Codex segments belong to the usage family and its style menu")
    func codexSegmentStyles() {
        #expect(MenuBarSegmentKind.codexSession.family == .usage)
        #expect(MenuBarSegmentKind.codexWeekly.family == .usage)
        #expect(MenuBarSegmentKind.codexSession.allowedStyles.contains(.labelValue))
        #expect(MenuBarSegmentKind.codexSession.allowedStyles.contains(.pill))
    }

    @Test("Codex popover elements belong to the usage family and its style menu")
    func codexPopoverElementStyles() {
        #expect(PopoverElementKind.codexSession.family == .usage)
        #expect(PopoverElementKind.codexWeekly.family == .usage)
        #expect(PopoverElementKind.codexSession.allowedStyles.contains(.gaugeRing))
        #expect(PopoverElementKind.codexWeekly.allowedStyles.contains(.chip))
        #expect(!PopoverElementKind.codexSession.isChrome)
    }

    /// The editor lists every case, so a new kind without a raw value that
    /// round-trips would corrupt a saved composition.
    @Test("Codex kinds round-trip through their raw values")
    func rawValueRoundTrip() {
        #expect(MenuBarSegmentKind(rawValue: "codexSession") == .codexSession)
        #expect(MenuBarSegmentKind(rawValue: "codexWeekly") == .codexWeekly)
        #expect(PopoverElementKind(rawValue: "codexSession") == .codexSession)
        #expect(PopoverElementKind(rawValue: "codexWeekly") == .codexWeekly)
        #expect(MenuBarSegmentKind.allCases.contains(.codexSession))
        #expect(PopoverElementKind.allCases.contains(.codexWeekly))
    }
}
