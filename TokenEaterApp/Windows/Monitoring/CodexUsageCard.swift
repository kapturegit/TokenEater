import SwiftUI

/// Dashboard card for the second vendor: Codex / ChatGPT usage next to Claude.
///
/// Shows both halves of the question the user actually asks - how much of each
/// window is burned, and how much is left - for the 5h and weekly limits, plus
/// the reset countdowns. When there is nothing to show it says which of the
/// three "nothing" cases applies (Codex not installed, signed in with an API
/// key, or a stale login), because the fix is different for each.
struct CodexUsageCard: View {
    @ObservedObject var store: CodexUsageStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore

    @State private var refreshHovering = false

    private let sessionWindow: TimeInterval = 5 * 3600
    private let weeklyWindow: TimeInterval = 7 * 86_400

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            header
            if store.hasData {
                windowRow(
                    label: String(localized: "codex.metric.session"),
                    icon: "clock.fill",
                    pct: store.sessionPct,
                    resetText: store.sessionReset,
                    resetDate: store.sessionResetDate,
                    windowDuration: sessionWindow
                )
                windowRow(
                    label: String(localized: "codex.metric.weekly"),
                    icon: "calendar",
                    pct: store.weeklyPct,
                    resetText: store.weeklyReset,
                    resetDate: store.weeklyResetDate,
                    windowDuration: weeklyWindow
                )
                footer
            } else {
                emptyState
            }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsGlass(radius: DS.Radius.card)
        .dsShadow(DS.Shadow.subtle)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: DS.Spacing.xs) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DS.Palette.accentStudio)
            Text(String(localized: "codex.title"))
                .font(DS.Typography.title2)
                .foregroundStyle(DS.Palette.textPrimary)

            if store.plan != .unknown {
                Text(store.plan.displayLabel)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
                            .fill(DS.Palette.accentStudio.opacity(0.25))
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
                                    .stroke(DS.Palette.accentStudio.opacity(0.5), lineWidth: 0.6)
                            )
                    )
            }

            if store.isRateLimited {
                Text(String(localized: "codex.limitReached"))
                    .font(DS.Typography.micro)
                    .foregroundStyle(DS.Palette.semanticError)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
                            .fill(DS.Palette.semanticError.opacity(0.15))
                    )
            }

            Spacer()

            if store.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 14, height: 14)
            }

            Button {
                Task { await store.refresh(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(refreshHovering ? DS.Palette.accentStudio : DS.Palette.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle().fill(refreshHovering ? DS.Palette.accentStudio.opacity(0.18) : DS.Palette.glassFill)
                    )
            }
            .buttonStyle(.plain)
            .help(String(localized: "codex.refresh"))
            .onHover { hovering in
                withAnimation(DS.Motion.springSnap) { refreshHovering = hovering }
            }
        }
    }

    // MARK: - One quota window

    private func windowRow(
        label: String,
        icon: String,
        pct: Int,
        resetText: String,
        resetDate: Date?,
        windowDuration: TimeInterval
    ) -> some View {
        let tint = gaugeColor(pct: pct, resetDate: resetDate, windowDuration: windowDuration)
        return VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.Palette.textTertiary)
                Text(label.uppercased())
                    .font(DS.Typography.micro)
                    .tracking(1.2)
                    .foregroundStyle(DS.Palette.textSecondary)
                Spacer()
                // The headline is what's LEFT, not what's spent: "38% left" is
                // the number you act on. Used stays next to it for continuity
                // with the Claude gauges, which are all utilization-first.
                Text(String(format: String(localized: "codex.remaining"), 100 - pct))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                Text(String(format: String(localized: "codex.used"), pct))
                    .font(DS.Typography.micro)
                    .monospacedDigit()
                    .foregroundStyle(DS.Palette.textTertiary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(DS.Palette.glassFillHi)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(min(max(pct, 0), 100)) / 100)
                }
            }
            .frame(height: 6)

            if !resetText.isEmpty {
                Text(String(format: String(localized: "metric.reset"), resetText))
                    .font(DS.Typography.micro)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: DS.Spacing.xs) {
            if let email = store.accountEmail, !email.isEmpty {
                Text(email)
                    .font(DS.Typography.micro)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let credits = store.credits, credits.unlimited || credits.hasCredits {
                Text(creditsLabel(credits))
                    .font(DS.Typography.micro)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            // A stale snapshot is worse than no snapshot if it's silent, so the
            // error is surfaced next to the numbers it applies to.
            if store.hasError {
                Text(errorText)
                    .font(DS.Typography.micro)
                    .foregroundStyle(DS.Palette.semanticWarning)
            }
        }
    }

    private func creditsLabel(_ credits: CodexCredits) -> String {
        if credits.unlimited { return String(localized: "codex.credits.unlimited") }
        let balance = credits.balance ?? "0"
        return String(format: String(localized: "codex.credits"), balance)
    }

    // MARK: - Empty / error states

    private var emptyState: some View {
        HStack(alignment: .top, spacing: DS.Spacing.xs) {
            Image(systemName: emptyGlyph)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Palette.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(emptyTitle)
                    .font(DS.Typography.label)
                    .foregroundStyle(DS.Palette.textSecondary)
                Text(emptyHint)
                    .font(DS.Typography.micro)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var emptyGlyph: String {
        switch store.authState {
        case .notInstalled: return "questionmark.folder"
        case .apiKeyMode:   return "key"
        case .expired:      return "clock.badge.exclamationmark"
        case .unreadable:   return "exclamationmark.triangle"
        case .ready:        return store.hasError ? "exclamationmark.triangle" : "hourglass"
        }
    }

    private var emptyTitle: String {
        switch store.authState {
        case .notInstalled: return String(localized: "codex.empty.notInstalled.title")
        case .apiKeyMode:   return String(localized: "codex.empty.apiKey.title")
        case .expired:      return String(localized: "codex.empty.expired.title")
        case .unreadable:   return String(localized: "codex.empty.unreadable.title")
        case .ready:        return store.hasError ? errorText : String(localized: "codex.empty.loading.title")
        }
    }

    private var emptyHint: String {
        switch store.authState {
        case .notInstalled: return String(localized: "codex.empty.notInstalled.hint")
        case .apiKeyMode:   return String(localized: "codex.empty.apiKey.hint")
        case .expired:      return String(localized: "codex.empty.expired.hint")
        case .unreadable:   return String(format: String(localized: "codex.empty.unreadable.hint"), store.credentialsPath)
        case .ready:        return store.hasError ? String(localized: "codex.empty.error.hint") : String(localized: "codex.empty.loading.hint")
        }
    }

    private var errorText: String {
        switch store.errorState {
        case .rateLimited:      return String(localized: "codex.error.rateLimited")
        case .networkError:     return String(localized: "codex.error.network")
        case .tokenUnavailable: return String(localized: "codex.empty.expired.title")
        case .none:             return ""
        }
    }

    // MARK: - Color

    /// Same resolver as every Claude surface, so a Codex gauge at 80% is the
    /// exact hue a Claude gauge at 80% would be (including Smart Color, which
    /// needs the real window length to weigh time-to-reset).
    private func gaugeColor(pct: Int, resetDate: Date?, windowDuration: TimeInterval) -> Color {
        GaugeColorResolver.color(
            mode: GaugeColorResolver.mode(smartColorEnabled: settingsStore.smartColorEnabled, windowDuration: windowDuration),
            utilization: pct,
            resetDate: resetDate,
            windowDuration: windowDuration,
            theme: themeStore.current,
            thresholds: themeStore.thresholds,
            pacingMargin: Double(settingsStore.pacingMargin),
            profile: settingsStore.smartColorProfile
        )
    }
}
