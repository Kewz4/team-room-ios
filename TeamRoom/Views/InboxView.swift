import SwiftUI

/// Everything that needs Kewz (decisions, questions from teammates, failed deliveries) and the updates feed.
struct InboxView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                let waiting = model.team.needsInput
                let failures = model.team.agents.filter { agent in (agent.queue ?? []).contains { ["failed", "interrupted"].contains($0.state ?? "") } }
                let decisions = (model.board.report?.decisions ?? []).filter { $0.kind == "plan" }
                if !waiting.isEmpty || !failures.isEmpty || !decisions.isEmpty {
                    Section("Needs you") {
                        ForEach(waiting) { agent in
                            Button { model.router.openAgent(agent.id) } label: {
                                InboxRow(worker: AgentStyle.worker(for: agent), title: "\(agent.displayName) is waiting for your answer",
                                         detail: agent.prompts?.first?.title ?? "Open the conversation to answer.", icon: "hand.raised.fill", tint: Tokens.working)
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(failures) { agent in
                            Button { model.router.openAgent(agent.id) } label: {
                                InboxRow(worker: AgentStyle.worker(for: agent), title: "\(agent.displayName) has a failed delivery",
                                         detail: (agent.queue ?? []).first { ["failed", "interrupted"].contains($0.state ?? "") }?.error ?? "Retry or edit it from the delivery queue.",
                                         icon: "exclamationmark.triangle.fill", tint: Tokens.failure)
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(decisions) { decision in
                            Button { model.router.tab = .board } label: {
                                InboxRow(worker: "kewz", title: decision.title, detail: decision.detail ?? "Decision for you on the board.", icon: "checklist", tint: Tokens.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section {
                    if model.notifications.ledger.notices.isEmpty {
                        Text("Finished tasks you sent, failures and requests for your input appear here.")
                            .font(TypeScale.footnote)
                            .foregroundStyle(Tokens.textSecondary)
                    }
                    ForEach(model.notifications.ledger.notices) { notice in
                        Button {
                            model.notifications.markRead(agentId: notice.agentId)
                            if !notice.agentId.isEmpty { model.router.openAgent(notice.agentId) }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                AgentAvatar(worker: AgentStyle.worker(forId: notice.agentId), size: 30)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text("\(notice.agentLabel) · \(notice.title)")
                                            .font(.subheadline.weight(notice.read ? .regular : .semibold))
                                            .foregroundStyle(Tokens.textPrimary)
                                        Spacer(minLength: 4)
                                        RelativeTimeText(iso: notice.time)
                                            .font(.caption2)
                                            .foregroundStyle(Tokens.textTertiary)
                                    }
                                    Text(notice.detail)
                                        .font(TypeScale.caption)
                                        .foregroundStyle(Tokens.textSecondary)
                                        .lineLimit(3)
                                }
                                if !notice.read {
                                    Circle().fill(Tokens.accent).frame(width: 8, height: 8).padding(.top, 6)
                                        .accessibilityLabel("Unread")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Updates")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Tokens.background)
            .navigationTitle("Inbox")
            .toolbar {
                SettingsToolbarItem(router: model.router)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Mark all read") { model.notifications.markRead() }
                        .disabled(model.notifications.unreadCount == 0)
                }
            }
            .refreshable { try? await model.refreshTeam() }
        }
    }
}

struct InboxRow: View {
    let worker: String
    let title: String
    let detail: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                AgentAvatar(worker: worker, size: 30)
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(tint, in: Circle())
                    .offset(x: 4, y: 4)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Tokens.textPrimary)
                Text(detail).font(TypeScale.caption).foregroundStyle(Tokens.textSecondary).lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
