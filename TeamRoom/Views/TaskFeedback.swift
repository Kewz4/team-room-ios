import SwiftUI

struct TaskFeedback: View {
    @Environment(AppModel.self) private var model
    let showWorkers: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: showWorkers) {
                HStack(spacing: 12) {
                    Label("\(count("working")) working", systemImage: "circle.dotted")
                    Label("\(count("completed")) finished", systemImage: "checkmark.circle")
                    if count("needs_input") > 0 { Label("\(count("needs_input")) need input", systemImage: "bubble.left") }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                }
                .font(TypeScale.captionMedium)
                .foregroundStyle(Tokens.textSecondary)
                .frame(minHeight: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("team-progress")

            if let agent = model.selectedAgent {
                let status = agent.taskStatus
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: symbol(status.kind)).foregroundStyle(color(status.kind))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(status.label).font(TypeScale.captionMedium)
                            if let date = TimeFormat.date(status.at) {
                                Text(date, style: .relative).font(TypeScale.caption).foregroundStyle(Tokens.textSecondary)
                            }
                        }
                        if let detail = status.detail, !detail.isEmpty {
                            Text(detail).font(TypeScale.caption).foregroundStyle(Tokens.textSecondary).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                    if status.kind == "completed" {
                        Button("Latest") {
                            model.scrollRequest += 1
                            model.notifications.markRead(agentId: agent.id)
                        }
                        .font(TypeScale.captionMedium)
                        .frame(minHeight: 36)
                    }
                }
                .accessibilityIdentifier("task-status")
            }
            if let error = model.syncError {
                Label("Connection interrupted. Showing the last saved status. \(error)", systemImage: "wifi.slash")
                    .font(TypeScale.caption).foregroundStyle(Tokens.failure).lineLimit(2)
            }
        }
        .padding(.horizontal, Tokens.Space.m)
        .padding(.vertical, Tokens.Space.s)
        .background(Tokens.background)
        .overlay(alignment: .bottom) { Rectangle().fill(Tokens.hairline).frame(height: 0.5) }
    }

    private func count(_ kind: String) -> Int { model.agents.filter { $0.taskStatus.kind == kind }.count }
    private func symbol(_ kind: String) -> String {
        switch kind {
        case "completed": return "checkmark.circle.fill"
        case "needs_input": return "bubble.left.fill"
        case "failed", "interrupted": return "exclamationmark.triangle.fill"
        case "working": return "circle.dotted"
        default: return "circle"
        }
    }
    private func color(_ kind: String) -> Color {
        ["failed", "interrupted", "disconnected"].contains(kind) ? Tokens.failure : kind == "completed" ? Tokens.idle : Tokens.working
    }
}

struct UpdatesInbox: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if model.notifications.ledger.notices.isEmpty {
                    ContentUnavailableView("No new updates", systemImage: "bell",
                        description: Text("Finished tasks, failures and requests for your input appear here after you connect."))
                }
                ForEach(model.notifications.ledger.notices) { notice in
                    Button {
                        model.select(notice.agentId)
                        model.notifications.markRead(agentId: notice.agentId)
                        model.scrollRequest += 1
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                if !notice.read { Circle().fill(Tokens.accent).frame(width: 6, height: 6) }
                                Text(notice.agentLabel).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(TimeFormat.relative(notice.time)).font(.caption2).foregroundStyle(.secondary)
                            }
                            Text(notice.title).font(.subheadline)
                            Text(notice.detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Team updates")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Mark all read") { model.notifications.markRead() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
