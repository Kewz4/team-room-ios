import SwiftUI

struct RoomView: View {
    @Environment(AppModel.self) private var model
    @State private var showSettings = false
    @State private var selectedEvent: LiveEvent?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TeammateBar()
                if let syncError = model.syncError {
                    Text("Sync issue: \(syncError)")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 4)
                }
                ConversationView(selectedEvent: $selectedEvent)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ComposerView()
            }
            .navigationTitle("Team Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SocketPill(note: model.socketNote)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
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
}

struct TeammateBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.agents) { agent in
                    Button {
                        model.select(agent.id)
                    } label: {
                        chip(agent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func chip(_ agent: Agent) -> some View {
        let selected = agent.id == model.selectedId
        return HStack(spacing: 8) {
            BrandIcon(provider: agent.provider ?? "")
                .foregroundStyle(.primary)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(agent.label)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(statusLine(agent))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Circle()
                .fill(stateColor(agent))
                .frame(width: 7, height: 7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(selected ? .regular.tint(.green.opacity(0.35)) : .regular, in: Capsule())
    }

    private func statusLine(_ agent: Agent) -> String {
        if agent.connection?.ready == false { return "connection needed" }
        switch agent.state {
        case "working":
            return agent.execution?.label ?? "working"
        case "idle":
            return "idle"
        default:
            return "unknown"
        }
    }

    private func stateColor(_ agent: Agent) -> Color {
        switch agent.state {
        case "working": return .orange
        case "idle": return .green
        default: return .gray
        }
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

struct SocketPill: View {
    let note: String

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var color: Color {
        switch note {
        case "live": return .green
        case "connecting", "reconnecting": return .orange
        default: return .gray
        }
    }

    private var label: String {
        note == "live" ? "live" : note
    }
}
