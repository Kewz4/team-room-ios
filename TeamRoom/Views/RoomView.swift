import SwiftUI

struct RoomView: View {
    @Environment(AppModel.self) private var model
    @State private var showWorkers = false
    @State private var showSettings = false
    @State private var selectedEvent: LiveEvent?

    var body: some View {
        NavigationStack {
            ConversationView(selectedEvent: $selectedEvent)
                .background(Tokens.background)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ComposerView()
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
                        menu
                    }
                }
        }
        .tint(Tokens.accent)
        .sheet(isPresented: $showWorkers) {
            WorkerSheet()
        }
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
        let state: String
        if agent.connection?.ready == false {
            state = "connection needed"
        } else if agent.state == "working" {
            state = agent.execution?.label ?? "working"
        } else {
            state = agent.state ?? "unknown"
        }
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
                    .foregroundStyle(Tokens.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Tokens.Space.s)
            if hasUsage {
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
        if agent.connection?.ready == false { return "Runner not connected" }
        switch agent.state {
        case "working":
            return agent.execution?.label ?? "Working"
        case "idle":
            return "Idle"
        default:
            return "Activity unknown"
        }
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
        case "opencode", "deepseek": return "brand-deepseek"
        default: return "brand-anthropic"
        }
    }
}
