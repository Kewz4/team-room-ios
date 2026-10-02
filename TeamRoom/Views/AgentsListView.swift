import SwiftUI

/// Every teammate's room, like a messages list: who is working, what on, the latest message, and anything
/// waiting (decisions for Kewz, queued relay work, holds, failed deliveries).
struct AgentsListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var router = model.router
        NavigationStack(path: $router.agentPath) {
            List {
                if !model.team.needsInput.isEmpty {
                    Section {
                        ForEach(model.team.needsInput) { agent in
                            NavigationLink(value: agent.id) {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "hand.raised.fill")
                                        .foregroundStyle(Tokens.working)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(agent.displayName) needs your input")
                                            .font(.subheadline.weight(.semibold))
                                        Text(agent.prompts?.first?.title ?? "Answer to let \(agent.displayName) continue")
                                            .font(TypeScale.caption)
                                            .foregroundStyle(Tokens.textSecondary)
                                            .lineLimit(3)
                                    }
                                }
                            }
                        }
                    }
                }
                Section {
                    ForEach(model.team.agents) { agent in
                        NavigationLink(value: agent.id) {
                            AgentRow(agent: agent)
                        }
                        .accessibilityIdentifier("agent-row-" + agent.id)
                    }
                } footer: {
                    if let relay = model.team.relay, let waiting = relay.waiting, waiting > 0 {
                        Text("\(waiting) relay request\(waiting == 1 ? "" : "s") waiting across the team\(relay.paused == true ? " · relay paused" : "").")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Tokens.background)
            .navigationTitle("Agents")
            .toolbar { SettingsToolbarItem(router: model.router) }
            .safeAreaInset(edge: .top, spacing: 0) { ConnectionBanner() }
            .refreshable { try? await model.refreshTeam() }
            .navigationDestination(for: String.self) { id in
                AgentRoomView(agentId: id)
            }
            .overlay {
                if model.team.agents.isEmpty {
                    EmptyStateView(title: "No teammates yet", message: "Waiting for the PC to report the team.", systemImage: "person.3")
                }
            }
        }
    }
}

struct AgentRow: View {
    let agent: Agent
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let worker = AgentStyle.worker(for: agent)
        let header = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(spacing: 6))
        HStack(alignment: .top, spacing: 12) {
            AgentAvatar(worker: worker, size: 42, state: agent.state, showRing: true)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                header {
                    Text(agent.displayName)
                        .font(.headline)
                        .foregroundStyle(Tokens.textPrimary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Text(agent.account ?? "")
                        .font(TypeScale.caption)
                        .foregroundStyle(Tokens.textTertiary)
                        .lineLimit(1)
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
                    if let time = agent.lastMessage?.time ?? agent.lastEventAt {
                        RelativeTimeText(iso: time)
                            .font(TypeScale.caption)
                            .foregroundStyle(Tokens.textTertiary)
                            .fixedSize()
                    }
                }
                Text(statusLine)
                    .font(.subheadline)
                    .foregroundStyle(statusColor)
                    .lineLimit(2)
                if let preview = agent.lastMessage?.text, !preview.isEmpty {
                    Text((agent.lastMessage?.role == "user" ? "Request: " : "") + preview)
                        .font(TypeScale.caption)
                        .foregroundStyle(Tokens.textSecondary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    if agent.quota?.held == true {
                        Pill(text: "Usage pause", color: Tokens.working, systemImage: "gauge.with.dots.needle.67percent")
                            .accessibilityLabel(agent.quota?.reason ?? "Paused for usage")
                    }
                    if let hold = agent.hold {
                        Pill(text: hold.until != nil ? "On hold" : "Reserve", color: Tokens.textSecondary, systemImage: "pause.circle")
                            .accessibilityLabel("Hold: \(hold.reason ?? "")")
                    }
                    if let waiting = agent.waiting, waiting > 0 {
                        Pill(text: "\(waiting) queued", color: Tokens.info, systemImage: "tray.full")
                    }
                    let failures = (agent.queue ?? []).filter { ["failed", "interrupted"].contains($0.state ?? "") }.count
                    if failures > 0 {
                        Pill(text: "\(failures) failed", color: Tokens.failure, systemImage: "exclamationmark.triangle")
                    }
                    Spacer(minLength: 0)
                    if let balance = agent.usage?.balance {
                        BalanceChip(balance: balance)
                    } else if agent.usage?.fiveHour != nil || agent.usage?.weekly != nil {
                        UsageBars(usage: agent.usage)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var statusLine: String {
        if agent.connection?.ready == false { return "Runner not connected" }
        if agent.state == "working" {
            let label = agent.execution?.label ?? agent.taskStatus.detail ?? "Working"
            return label.isEmpty ? "Working" : label
        }
        let status = agent.taskStatus
        return status.label + (status.kind == "completed" || status.kind == "idle" ? "" : (status.detail.map { " — " + $0 } ?? ""))
    }

    private var statusColor: Color {
        if agent.connection?.ready == false { return Tokens.failure }
        if !(agent.prompts ?? []).isEmpty { return Tokens.working }
        switch agent.state {
        case "working": return Tokens.working
        default: return Tokens.textSecondary
        }
    }
}
