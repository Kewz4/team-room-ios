import SwiftUI

enum StreamRow: Identifiable {
    case message(ChatMessage)
    case event(LiveEvent)

    var id: String {
        switch self {
        case .message(let message): return "m-" + message.id
        case .event(let event): return "e-" + event.id
        }
    }

    var time: Date? {
        switch self {
        case .message(let message): return TimeFormat.date(message.time)
        case .event(let event): return TimeFormat.date(event.time)
        }
    }
}

struct ConversationView: View {
    @Environment(AppModel.self) private var model
    @Binding var selectedEvent: LiveEvent?

    private let bottomID = "conversation-bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let agent = model.selectedAgent {
                        ForEach(rows(for: agent)) { row in
                            switch row {
                            case .message(let message):
                                MessageRow(message: message)
                            case .event(let event):
                                EventRow(event: event) { selectedEvent = event }
                            }
                        }
                        QueueSection(agent: agent)
                        if let live = agent.liveText, !live.isEmpty {
                            LiveReplyRow(text: live)
                        }
                    } else {
                        ContentUnavailableView("No teammate selected", systemImage: "person.2")
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(bottomID)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: scrollTick) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
            }
            .onAppear {
                proxy.scrollTo(bottomID, anchor: .bottom)
            }
        }
    }

    private var scrollTick: String {
        guard let agent = model.selectedAgent else { return model.selectedId }
        let messages = agent.messages?.count ?? 0
        let live = agent.liveText?.count ?? 0
        let queue = agent.queue?.count ?? 0
        return "\(model.selectedId)-\(messages)-\(live)-\(queue)"
    }

    private func rows(for agent: Agent) -> [StreamRow] {
        let messages = (agent.messages ?? []).map(StreamRow.message)
        let events = (agent.events ?? []).map(StreamRow.event)
        return (messages + events).sorted { ($0.time ?? .distantPast) < ($1.time ?? .distantPast) }
    }
}

struct MessageRow: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 44) }
            Text(message.text ?? "")
                .font(.callout)
                .textSelection(.enabled)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(
                    isUser ? AnyShapeStyle(Color.green.opacity(0.22)) : AnyShapeStyle(.thinMaterial),
                    in: RoundedRectangle(cornerRadius: 18)
                )
            if !isUser { Spacer(minLength: 44) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}

struct QueueSection: View {
    @Environment(AppModel.self) private var model
    let agent: Agent

    var body: some View {
        let items = (agent.queue ?? []).filter { ($0.text ?? "").isEmpty == false }
        if !items.isEmpty {
            VStack(alignment: .trailing, spacing: 8) {
                ForEach(items) { item in
                    HStack {
                        Spacer(minLength: 44)
                        VStack(alignment: .trailing, spacing: 6) {
                            Text(item.text ?? "")
                                .font(.callout)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 9)
                                .background(Color.green.opacity(0.14), in: RoundedRectangle(cornerRadius: 18))
                            HStack(spacing: 10) {
                                Text(queueLabel(item))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if canCancel(item) {
                                    Button("Cancel") {
                                        Task { await model.cancelQueued(id: item.id) }
                                    }
                                    .font(.caption2)
                                }
                                if canRetry(item) {
                                    Button("Retry") {
                                        Task { await model.retryMessage(id: item.id) }
                                    }
                                    .font(.caption2)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func queueLabel(_ item: ChatMessage) -> String {
        switch item.state {
        case "queued": return "Queued"
        case "waiting_busy": return "Waiting for the current turn to finish"
        case "waiting_connection": return "Waiting for the runner connection"
        case "sending": return "Sending…"
        case "streaming": return "Working…"
        case "failed": return "Failed — \(item.error ?? "unknown error")"
        case "interrupted": return "Interrupted"
        default: return item.state ?? "Pending"
        }
    }

    private func canCancel(_ item: ChatMessage) -> Bool {
        ["queued", "waiting_busy", "waiting_connection"].contains(item.state ?? "")
    }

    private func canRetry(_ item: ChatMessage) -> Bool {
        ["failed", "interrupted"].contains(item.state ?? "")
    }
}

struct LiveReplyRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.callout)
                    .textSelection(.enabled)
                BlinkingDot()
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
            Spacer(minLength: 44)
        }
    }
}

struct BlinkingDot: View {
    @State private var dim = false

    var body: some View {
        Circle()
            .frame(width: 7, height: 7)
            .opacity(dim ? 0.25 : 1)
            .animation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true), value: dim)
            .onAppear { dim = true }
    }
}

struct EventRow: View {
    let event: LiveEvent
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: EventStyle.symbol(for: event))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(EventStyle.color(for: event))
                    .frame(width: 16, height: 16)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    if let preview = event.detailPreview, !preview.isEmpty {
                        Text(preview.replacingOccurrences(of: "\r", with: ""))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 6)
                Text(TimeFormat.relative(event.time))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

enum EventStyle {
    static func symbol(for event: LiveEvent) -> String {
        if event.status == "failed" || event.kind == "error" { return "exclamationmark.triangle" }
        switch event.action ?? event.kind {
        case "command": return "terminal"
        case "files", "file": return "doc.text"
        case "image": return "photo"
        case "browser": return "globe"
        case "agents": return "person.2"
        case "waiting": return "hourglass"
        case "output": return "text.alignleft"
        case "status", "notice": return "info.circle"
        default: return "wrench.and.screwdriver"
        }
    }

    static func color(for event: LiveEvent) -> Color {
        if event.status == "failed" || event.kind == "error" { return .red }
        if event.status == "running" { return .orange }
        return .secondary
    }
}

struct EventDetailSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let agentId: String
    let event: LiveEvent
    @State private var detail: EventDetail?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(event.title)
                        .font(.headline)
                    HStack(spacing: 8) {
                        Text(event.kind)
                        if let status = event.status { Text(status) }
                        if let time = TimeFormat.date(event.time) {
                            Text(time.formatted(date: .abbreviated, time: .standard))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if let text = detail?.detail ?? event.detailPreview, !text.isEmpty {
                        Text(text)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Activity detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { detail = await model.detail(for: event) }
        }
    }
}
