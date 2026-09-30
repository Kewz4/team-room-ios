import SwiftUI

struct RoomView: View {
    @Environment(AppModel.self) private var model
    @State private var showWorkers = false
    @State private var showSettings = false
    @State private var showUpdates = false
    @State private var showDeliveries = false
    @State private var selectedEvent: LiveEvent?

    var body: some View {
        NavigationStack {
            ConversationView(selectedEvent: $selectedEvent)
                .id(model.selectedId)
                .background(Tokens.background)
            .safeAreaInset(edge: .top, spacing: 0) {
                TaskFeedback { showWorkers = true }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if let agent = model.selectedAgent, let prompt = agent.prompts?.first {
                        DecisionCard(agentId: agent.id, prompt: prompt, extraCount: (agent.prompts?.count ?? 1) - 1)
                            .id(prompt.id)
                            .padding(.horizontal, Tokens.Space.m)
                            .padding(.bottom, Tokens.Space.s)
                    }
                    ComposerView()
                }
            }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showWorkers = true
                        } label: {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 17, weight: .medium))
                        }
                        .accessibilityLabel("Teammates")
                    }
                    ToolbarItem(placement: .principal) {
                        header
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showUpdates = true } label: {
                            Image(systemName: model.notifications.unreadCount > 0 ? "bell.badge" : "bell")
                        }
                        .accessibilityLabel("Team updates, \(model.notifications.unreadCount) unread")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        menu
                    }
                }
        }
        .tint(Tokens.accent)
        .environment(\.openURL, model.linkAction())
        .sheet(item: Binding(get: { model.artifact }, set: { model.artifact = $0 })) { request in
            ArtifactPreview(request: request)
        }
        .sheet(isPresented: $showDeliveries) { DeliveryCenter(agentId: model.selectedId) }
        .sheet(isPresented: $showWorkers) {
            WorkerSheet()
        }
        .sheet(isPresented: $showUpdates) { UpdatesInbox() }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(item: $selectedEvent) { event in
            EventDetailSheet(agentId: event.agentId ?? model.selectedId, event: event)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.actionError != nil },
            set: { if !$0 { model.actionError = nil } }
        )) {
            Button("OK", role: .cancel) { model.actionError = nil }
        } message: {
            Text(model.actionError ?? "")
        }
    }

    private var header: some View {
        VStack(spacing: 1) {
            Text(model.selectedAgent?.label ?? "Team Room")
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 4) {
                Circle()
                    .fill(socketColor)
                    .frame(width: 5, height: 5)
                Text(headerSubtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: 230)
    }

    private var headerSubtitle: String {
        guard let agent = model.selectedAgent else { return "not connected" }
        let state = agent.taskStatus.label
        let account = agent.account ?? ""
        return account.isEmpty ? state : "\(account) · \(state)"
    }

    private var socketColor: Color {
        switch model.socketNote {
        case "live": return Tokens.idle
        case "connecting", "reconnecting": return Tokens.working
        default: return Tokens.textTertiary
        }
    }

    private var menu: some View {
        Menu {
            Button {
                showDeliveries = true
            } label: {
                Label("Delivery queue", systemImage: "tray")
            }
            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            Button {
                model.refresh()
            } label: {
                Label("Refresh now", systemImage: "arrow.clockwise")
            }
            Button {
                Task { await model.checkRunners() }
            } label: {
                Label("Recheck runners", systemImage: "stethoscope")
            }
            Divider()
            Button(role: .destructive) {
                model.signOut()
            } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("More")
    }
}

struct WorkerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.agents) { agent in
                    Button {
                        model.select(agent.id)
                        dismiss()
                    } label: {
                        WorkerRow(agent: agent, selected: agent.id == model.selectedId)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Tokens.surface)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Tokens.background)
            .navigationTitle("Teammates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct WorkerRow: View {
    let agent: Agent
    let selected: Bool

    var body: some View {
        HStack(spacing: Tokens.Space.m) {
            ZStack {
                RoundedRectangle(cornerRadius: Tokens.Radius.s, style: .continuous)
                    .fill(Tokens.accentSoft)
                    .frame(width: 36, height: 36)
                BrandIcon(provider: agent.provider ?? "")
                    .foregroundStyle(Tokens.accent)
                    .frame(width: 20, height: 20)
            }
            VStack(alignment: .leading, spacing: Tokens.Space.hair) {
                HStack(spacing: Tokens.Space.s) {
                    Text(agent.label)
                        .font(TypeScale.subhead)
                        .foregroundStyle(Tokens.textPrimary)
                    Circle()
                        .fill(stateColor)
                        .frame(width: 6, height: 6)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Tokens.accent)
                    }
                }
                Text("\(agent.account ?? "") · \(agent.modelLabel ?? "")")
                    .font(TypeScale.caption)
                    .foregroundStyle(Tokens.textSecondary)
                    .lineLimit(1)
                Text(statusLine)
                    .font(TypeScale.caption)
                    .foregroundStyle(agent.prompts?.isEmpty == false ? Tokens.working : Tokens.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Tokens.Space.s)
            if let balance = agent.usage?.balance {
                BalanceChip(balance: balance)
            } else if hasUsage {
                UsageBars(usage: agent.usage)
            }
        }
        .padding(.vertical, Tokens.Space.xs)
        .contentShape(Rectangle())
    }

    private var hasUsage: Bool {
        agent.usage?.fiveHour != nil || agent.usage?.weekly != nil
    }

    private var statusLine: String {
        let status = agent.taskStatus
        return status.label + (status.at.map { " · " + TimeFormat.relative($0) } ?? "")
    }

    private var stateColor: Color {
        switch agent.state {
        case "working": return Tokens.working
        case "idle": return Tokens.idle
        default: return Tokens.textTertiary
        }
    }
}

/// Compact per-window usage: a 5-hour bar and a weekly bar, colored by pressure.
struct UsageBars: View {
    let usage: AgentUsage?

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            if let fiveHour = usage?.fiveHour {
                bar(label: "5h", value: fiveHour)
            }
            if let weekly = usage?.weekly {
                bar(label: "wk", value: weekly)
            }
        }
    }

    private func bar(label: String, value: Double) -> some View {
        HStack(spacing: Tokens.Space.xs) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Tokens.textTertiary)
                .frame(width: 14, alignment: .trailing)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Tokens.surfaceAlt)
                    .frame(width: 44, height: 4)
                Capsule()
                    .fill(color(value))
                    .frame(width: max(3, 44 * min(max(value, 0), 100) / 100), height: 4)
            }
            Text("\(Int(value.rounded()))%")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Tokens.textSecondary)
                .frame(width: 30, alignment: .trailing)
        }
    }

    private func color(_ value: Double) -> Color {
        if value >= 95 { return Tokens.failure }
        if value >= 80 { return Tokens.working }
        return Tokens.accent
    }
}

/// Pre-paid accounts report a balance rather than usage windows: a compact amount, or a dash when unknown.
struct BalanceChip: View {
    let balance: AgentBalance

    var body: some View {
        HStack(spacing: Tokens.Space.xs) {
            Image(systemName: "creditcard")
                .font(.system(size: 10))
                .foregroundStyle(Tokens.textTertiary)
            Text(balance.displayAmount ?? "—")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
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
