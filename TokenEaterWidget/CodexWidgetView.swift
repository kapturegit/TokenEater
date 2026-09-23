import SwiftUI
import WidgetKit

// =====================================================================
// MARK: - Codex (Small + Medium)
//
// The second vendor on the desktop: the ChatGPT plan's 5h and weekly
// Codex windows, and how much of each is left. Both windows are plain
// rolling quotas, so they colour through the same Smart Color path as
// the Claude gauges - a Codex ring at 80% is the exact hue a Claude
// ring at 80% would be.
//
// `entry.codexUsage == nil` means the user has not turned Codex
// tracking on (the app only writes the key once it does), which is a
// different state from "no data" and gets its own copy.
// =====================================================================

struct CodexWidgetView: View {
    let entry: UsageEntry

    @Environment(\.widgetFamily) var family
    private var theme: ThemeColors { WidgetTheme.theme }
    private var thresholds: UsageThresholds { WidgetTheme.thresholds }

    private let sessionWindow: TimeInterval = 5 * 3600
    private let weeklyWindow: TimeInterval = 7 * 86_400

    var body: some View {
        Group {
            if let codex = entry.codexUsage {
                switch family {
                case .systemMedium: mediumContent(codex)
                default: smallContent(codex)
                }
            } else {
                notTrackedContent
            }
        }
        .widgetURL(URL(string: "tokeneater://open"))
        .modifier(WidgetBackgroundModifier())
    }

    // MARK: - Small : the 5h ring, the window that actually interrupts you

    private func smallContent(_ codex: CodexUsageResponse) -> some View {
        let window = codex.sessionWindow
        let pct = window?.percent ?? 0
        let resetDate = window?.resetsAtDate()
        let color = gaugeColor(pct: pct, resetDate: resetDate, windowDuration: sessionWindow)
        let gradient = gaugeGradient(pct: pct, resetDate: resetDate, windowDuration: sessionWindow)

        return VStack(spacing: 0) {
            WidgetHeader("widget.title.codex")
            Spacer(minLength: 8)
            ZStack {
                Circle()
                    .stroke(.white.opacity(WidgetTokens.trackOpacity), lineWidth: WidgetTokens.ringSmall)
                Circle()
                    .trim(from: 0, to: min(Double(pct), 100) / 100)
                    .stroke(gradient, style: StrokeStyle(lineWidth: WidgetTokens.ringSmall, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(0.32), radius: 5)
                HeroPercent(pct)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
            Spacer(minLength: 8)
            Text(remainingText(pct: pct, resetText: countdown(resetDate, short: true)))
                .font(WidgetTokens.microMono)
                .foregroundStyle(Color(hex: theme.widgetText).opacity(WidgetTokens.secondary))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    // MARK: - Medium : both windows as bars, left-first

    private func mediumContent(_ codex: CodexUsageResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader("widget.title.codex") {
                if codex.plan != .unknown {
                    Text(codex.plan.displayLabel)
                        .font(WidgetTokens.micro)
                        .foregroundStyle(Color(hex: theme.widgetText).opacity(WidgetTokens.tertiary))
                }
            }

            windowRow(
                label: String(localized: "widget.codex.session"),
                window: codex.sessionWindow,
                windowDuration: sessionWindow,
                shortCountdown: true
            )
            windowRow(
                label: String(localized: "widget.codex.weekly"),
                window: codex.weeklyWindow,
                windowDuration: weeklyWindow,
                shortCountdown: false
            )

            Spacer(minLength: 0)
        }
    }

    private func windowRow(
        label: String,
        window: CodexRateLimitWindow?,
        windowDuration: TimeInterval,
        shortCountdown: Bool
    ) -> some View {
        let pct = window?.percent ?? 0
        let resetDate = window?.resetsAtDate()
        let color = gaugeColor(pct: pct, resetDate: resetDate, windowDuration: windowDuration)
        let gradient = gaugeGradient(
            pct: pct, resetDate: resetDate, windowDuration: windowDuration,
            startPoint: .leading, endPoint: .trailing
        )

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(label.uppercased())
                    .font(WidgetTokens.micro)
                    .foregroundStyle(Color(hex: theme.widgetText).opacity(WidgetTokens.tertiary))
                Spacer(minLength: 0)
                // Remaining leads: it's the number you act on.
                Text(String(format: String(localized: "codex.remaining"), 100 - pct))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                let reset = countdown(resetDate, short: shortCountdown)
                if !reset.isEmpty {
                    Text(reset)
                        .font(WidgetTokens.microMono)
                        .foregroundStyle(Color(hex: theme.widgetText).opacity(WidgetTokens.tertiary))
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(WidgetTokens.trackOpacity))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(gradient)
                        .frame(width: max(0, geo.size.width * min(Double(pct), 100) / 100))
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: - Not-tracked state

    private var notTrackedContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.title3)
                .foregroundStyle(Color(hex: theme.widgetText).opacity(WidgetTokens.tertiary))
            Text("widget.codex.notTracked")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color(hex: theme.widgetText).opacity(WidgetTokens.secondary))
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Helpers

    private func remainingText(pct: Int, resetText: String) -> String {
        let left = String(format: String(localized: "codex.remaining"), 100 - pct)
        return resetText.isEmpty ? left : "\(left) · \(resetText)"
    }

    private func countdown(_ date: Date?, short: Bool) -> String {
        guard let date else { return "" }
        return short
            ? ResetCountdownFormatter.session(from: date).relative
            : ResetCountdownFormatter.weekly(from: date).relative
    }

    private func gaugeColor(pct: Int, resetDate: Date?, windowDuration: TimeInterval) -> Color {
        GaugeColorResolver.color(
            mode: GaugeColorResolver.mode(
                smartColorEnabled: WidgetTheme.smartColorEnabled,
                windowDuration: windowDuration
            ),
            utilization: pct,
            resetDate: resetDate,
            windowDuration: windowDuration,
            theme: theme,
            thresholds: thresholds,
            // The pacing-margin slider is not mirrored into shared.json, so the
            // widget uses the same default the app ships with. Same value every
            // other widget's Smart Color call effectively uses.
            pacingMargin: 10,
            profile: WidgetTheme.smartColorProfile
        )
    }

    private func gaugeGradient(
        pct: Int,
        resetDate: Date?,
        windowDuration: TimeInterval,
        startPoint: UnitPoint = .top,
        endPoint: UnitPoint = .bottom
    ) -> LinearGradient {
        GaugeColorResolver.gradient(
            mode: GaugeColorResolver.mode(
                smartColorEnabled: WidgetTheme.smartColorEnabled,
                windowDuration: windowDuration
            ),
            utilization: pct,
            resetDate: resetDate,
            windowDuration: windowDuration,
            theme: theme,
            thresholds: thresholds,
            pacingMargin: 10,
            profile: WidgetTheme.smartColorProfile,
            startPoint: startPoint,
            endPoint: endPoint
        )
    }
}
