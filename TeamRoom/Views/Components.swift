import SwiftUI

/// Round avatar in the teammate's colour, with an optional ring showing whether they are working.
struct AgentAvatar: View {
    let worker: String
    var size: CGFloat = 36
    var state: String?
    var showRing = false

    var body: some View {
        let color = AgentStyle.color(worker)
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [color, color.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(AgentStyle.displayName(worker).prefix(1))
                .font(.system(size: size * 0.44, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .overlay {
            if showRing {
                Circle()
                    .stroke(AgentStyle.stateColor(state), lineWidth: 2)
                    .padding(-3)
            }
        }
        .accessibilityHidden(true)
    }
}

struct StatusDot: View {
    let state: String?
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(AgentStyle.stateColor(state))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Small capsule label, e.g. "Working", "Blocked", "2 waiting".
struct Pill: View {
    let text: String
    var color: Color = Tokens.textSecondary
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.caption2.weight(.semibold)) }
            Text(text).font(.caption2.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }
}

/// Compact 5-hour + weekly usage bars, colour-coded by pressure.
struct UsageBars: View {
    let usage: AgentUsage?
    // Scales with Dynamic Type (the 1.0 large-text screenshot showed fixed 10 pt labels).
    @ScaledMetric(relativeTo: .caption2) private var textSize: CGFloat = 10
    @ScaledMetric(relativeTo: .caption2) private var labelWidth: CGFloat = 14
    @ScaledMetric(relativeTo: .caption2) private var valueWidth: CGFloat = 30
    @ScaledMetric(relativeTo: .caption2) private var barWidth: CGFloat = 40

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            if let fiveHour = usage?.fiveHour { bar(label: "5h", value: fiveHour) }
            if let weekly = usage?.weekly { bar(label: "wk", value: weekly) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if let fiveHour = usage?.fiveHour { parts.append("5-hour usage \(Int(fiveHour)) percent") }
        if let weekly = usage?.weekly { parts.append("weekly usage \(Int(weekly)) percent") }
        return parts.joined(separator: ", ")
    }

    private func bar(label: String, value: Double) -> some View {
        HStack(spacing: Tokens.Space.xs) {
            Text(label)
                .font(.system(size: textSize))
                .foregroundStyle(Tokens.textTertiary)
                .frame(width: labelWidth, alignment: .trailing)
            ZStack(alignment: .leading) {
                Capsule().fill(Tokens.surfaceAlt).frame(width: barWidth, height: 4)
                Capsule().fill(Self.color(value)).frame(width: max(3, barWidth * min(max(value, 0), 100) / 100), height: 4)
            }
            Text("\(Int(value.rounded()))%")
                .font(.system(size: textSize, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(Tokens.textSecondary)
                .frame(width: valueWidth, alignment: .trailing)
        }
    }

    static func color(_ value: Double) -> Color {
        if value >= 95 { return Tokens.failure }
        if value >= 80 { return Tokens.working }
        return Tokens.accent
    }
}

/// Pre-paid accounts report a balance rather than usage windows.
struct BalanceChip: View {
    let balance: AgentBalance

    var body: some View {
        HStack(spacing: Tokens.Space.xs) {
            Image(systemName: "creditcard")
                .font(.system(size: 10))
                .foregroundStyle(Tokens.textTertiary)
            Text(balance.displayAmount ?? "—")
                .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(balance.hasAmount ? Tokens.textSecondary : Tokens.textTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(balance.hasAmount ? "Balance \(balance.displayAmount ?? "")" : "Balance not reported")
    }
}

struct BrandIcon: View {
    let provider: String

    var body: some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
    }

    private var name: String {
        switch provider {
        case "codex": return "brand-openai"
        case "claude": return "brand-claude"
        case "dsh", "opencode", "deepseek": return "brand-deepseek"
        default: return "brand-anthropic"
        }
    }
}

/// Thin banner under the navigation bar while the live connection is down.
struct ConnectionBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.phase == .ready, model.socketStatus != .live || model.syncError != nil {
            HStack(spacing: Tokens.Space.s) {
                if model.socketStatus == .connecting || model.socketStatus == .reconnecting {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "wifi.slash").font(.caption.weight(.semibold))
                }
                Text(message)
                    .font(TypeScale.caption)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Button("Retry") { model.refresh() }
                    .font(TypeScale.captionMedium)
                    .buttonStyle(.borderless)
            }
            .foregroundStyle(model.socketStatus == .offline ? Tokens.failure : Tokens.working)
            .padding(.horizontal, Tokens.Space.m)
            .padding(.vertical, 6)
            .background(.bar)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityIdentifier("connection-banner")
        }
    }

    private var message: String {
        switch model.socketStatus {
        case .connecting: return "Connecting to your PC…"
        case .reconnecting: return "Reconnecting… showing the last update" + (model.team.lastSync.map { " from " + $0.formatted(date: .omitted, time: .shortened) } ?? "")
        case .offline: return model.syncError ?? "Offline. Showing the last saved state."
        case .live: return model.syncError ?? ""
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    var systemImage: String = "sparkles"

    var body: some View {
        VStack(spacing: Tokens.Space.s) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(Tokens.textTertiary)
            Text(title)
                .font(.headline)
                .foregroundStyle(Tokens.textPrimary)
            Text(message)
                .font(TypeScale.footnote)
                .foregroundStyle(Tokens.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Tokens.Space.xl)
        .padding(.horizontal, Tokens.Space.l)
    }
}

/// Relative time that refreshes itself ("2 min ago") without redrawing the parent every second.
struct RelativeTimeText: View {
    let iso: String?
    var prefix = ""

    var body: some View {
        if let date = TimeFormat.date(iso) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(prefix + TimeFormat.relative(date, now: context.date))
            }
        }
    }
}

/// Animated "Nova is reading the board…" line used while a teammate works.
struct ActivityLine: View {
    let text: String
    var color: Color = Tokens.textSecondary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(color)
                        .frame(width: 5, height: 5)
                        .opacity(reduceMotion ? 0.7 : (phase ? (index == 1 ? 1 : 0.35) : (index == 1 ? 0.35 : 1)))
                }
            }
            Text(text)
                .font(TypeScale.caption)
                .foregroundStyle(color)
                .lineLimit(2)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { phase = true }
        }
        .accessibilityElement(children: .combine)
    }
}

extension TimeFormat {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static func relative(_ date: Date, now: Date = Date()) -> String {
        if abs(now.timeIntervalSince(date)) < 45 { return "just now" }
        return relativeFormatter.localizedString(for: date, relativeTo: now)
    }
}
