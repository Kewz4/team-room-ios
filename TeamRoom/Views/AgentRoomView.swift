import SwiftUI

/// One teammate's room: their real conversation (messages, compact activity groups, the reply streaming live),
/// pending decisions, the delivery queue and a composer.
struct AgentRoomView: View {
    let agentId: String
    @Environment(AppModel.self) private var model
    @State private var selectedEvent: LiveEvent?
    @State private var showDeliveries = false
    @State private var focus: String?
    @FocusState private var composerFocused: Bool

    var body: some View {
        let store = model.conversation(agentId)
        let agent = model.team.agent(agentId)
        ChatScroll(followKey: followKey(store), focus: $focus) {
            if store.items.isEmpty {
                if store.loaded || !store.loading {
                    EmptyStateView(title: "No conversation yet", message: "Send the first message to \(agent?.displayName ?? "this teammate") below.", systemImage: "bubble.left")
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, Tokens.Space.xl)
                }
            }
            ForEach(store.items) { item in
                switch item {
                case .message(let message):
                    MessageRow(agentId: agentId, message: message, name: agent?.displayName ?? "Teammate", worker: agent.map(AgentStyle.worker(for:)) ?? "")
                        .id(item.id)
                case .activity(let group):
                    ActivityGroupRow(agentId: agentId, group: group) { selectedEvent = $0 }
                        .id(item.id)
                }
            }
            if let live = store.visibleLiveText {
                LiveTextRow(text: live, worker: agent.map(AgentStyle.worker(for:)) ?? "")
                    .id("live")
            }
            QueueSection(agentId: agentId, store: store) { showDeliveries = true }
        }
        .background(Tokens.background)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                ConnectionBanner()
                if let agent { AgentStatusStrip(agent: agent) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if let prompt = store.prompts.first ?? agent?.prompts?.first {
                    DecisionCard(agentId: agentId, prompt: prompt, extraCount: max(store.prompts.count, agent?.prompts?.count ?? 0) - 1)
                        .id(prompt.id)
                        .padding(.horizontal, Tokens.Space.m)
                        .padding(.bottom, Tokens.Space.s)
                }
                AgentComposer(agentId: agentId, focused: $composerFocused)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(agent?.displayName ?? "Teammate").font(.headline)
                    Text([agent?.account, agent?.modelLabel].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(Tokens.textSecondary)
                        .lineLimit(1)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showDeliveries = true } label: { Label("Delivery queue", systemImage: "tray") }
                    Button { Task { await model.refreshConversation(agentId, force: true) } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    Button { Task { await model.checkRunners() } } label: { Label("Recheck runners", systemImage: "stethoscope") }
                } label: { Image(systemName: "ellipsis") }
                .accessibilityLabel("More")
            }
            if composerFocused {
                ToolbarItem(placement: .topBarTrailing) { HideKeyboardButton { composerFocused = false } }
            }
        }
        .sheet(isPresented: $showDeliveries) { DeliveryCenter(agentId: agentId) }
        .sheet(item: $selectedEvent) { event in
            EventDetailSheet(agentId: agentId, event: event)
        }
        .onAppear { model.conversationAppeared(agentId) }
        .onDisappear { model.conversationDisappeared(agentId) }
    }

    private func followKey(_ store: ConversationStore) -> Int {
        store.items.count &* 31 &+ store.liveText.utf16.count &+ store.queue.count &* 7
    }
}

/// What the teammate is doing right now, under the navigation bar.
struct AgentStatusStrip: View {
    let agent: Agent
    @Environment(AppModel.self) private var model

    var body: some View {
        let status = agent.taskStatus
        HStack(spacing: 8) {
            StatusDot(state: agent.state)
            Text(line(status))
                .font(TypeScale.caption)
                .foregroundStyle(Tokens.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if agent.canStop == true {
                Button(role: .destructive) {
                    Task { await model.stopTurn(agent.id) }
                } label: {
                    Label("Stop", systemImage: "stop.circle")
                        .font(TypeScale.captionMedium)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(Tokens.failure)
            }
        }
        .padding(.horizontal, Tokens.Space.m)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Rectangle().fill(Tokens.hairline).frame(height: 0.5) }
        .accessibilityIdentifier("task-status")
    }

    private func line(_ status: TaskStatus) -> String {
        var parts = [status.label]
        if let detail = status.detail, !detail.isEmpty, status.kind != "idle" { parts.append(detail) }
        if agent.quota?.held == true, let reason = agent.quota?.reason { parts.append(reason) }
        if let hold = agent.hold, let reason = hold.reason { parts.append("Hold: " + reason) }
        return parts.joined(separator: " · ")
    }
}

struct AgentComposer: View {
    let agentId: String
    /// Owned by the room, so its navigation bar can show the hide-keyboard button (1.2).
    @FocusState.Binding var focused: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if steerable {
                // 1.1 steering: while a Team Room turn runs, a message goes into that turn instead of waiting behind it.
                Label("Goes into \(name)'s current turn · hold send to queue instead", systemImage: "arrow.turn.down.right")
                    .font(TypeScale.caption)
                    .foregroundStyle(Tokens.textTertiary)
                    .lineLimit(1)
                    .padding(.horizontal, Tokens.Space.s)
                    .accessibilityIdentifier("steer-hint")
            }
            composerRow
        }
        .padding(.horizontal, Tokens.Space.m)
        .padding(.vertical, Tokens.Space.s)
    }

    private var steerable: Bool { model.team.agent(agentId)?.steerable == true }
    private var name: String { model.team.agent(agentId)?.displayName ?? "the teammate" }

    private var composerRow: some View {
        HStack(alignment: .bottom, spacing: Tokens.Space.s) {
            TextField(placeholder, text: draft, axis: .vertical)
                .font(TypeScale.body)
                .lineLimit(1...6)
                .focused($focused)
                .padding(.horizontal, Tokens.Space.m)
                .padding(.vertical, 11)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .accessibilityIdentifier("agent-composer")
            Button {
                let text = draft.wrappedValue
                Task { await model.send(text, to: agentId) }
            } label: {
                Group {
                    if model.sendingTo.contains(agentId) {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: steerable ? "arrow.turn.down.right" : "arrow.up").font(.system(size: 16, weight: .semibold))
                    }
                }
                .frame(width: 42, height: 42)
            }
            .buttonStyle(.glassProminent)
            .tint(Tokens.accent)
            .clipShape(Circle())
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.5)
            .contextMenu {
                if steerable {
                    Button("Queue after this turn", systemImage: "tray.and.arrow.down") {
                        let text = draft.wrappedValue
                        Task { await model.send(text, to: agentId, mode: "queue") }
                    }
                    Button("Steer into this turn", systemImage: "arrow.turn.down.right") {
                        let text = draft.wrappedValue
                        Task { await model.send(text, to: agentId, mode: "steer") }
                    }
                }
            }
            .accessibilityLabel(steerable ? "Steer message into the current turn" : "Send message")
            .accessibilityIdentifier("send-button")
            .sensoryFeedback(.impact(weight: .light), trigger: model.sendingTo.contains(agentId)) { old, new in !old && new }
        }
    }

    private var draft: Binding<String> {
        Binding(get: { model.drafts[agentId] ?? "" }, set: { model.drafts[agentId] = $0 })
    }

    private var placeholder: String {
        "Message \(model.team.agent(agentId)?.displayName ?? "teammate")"
    }

    private var canSend: Bool {
        !(model.drafts[agentId] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.sendingTo.contains(agentId)
    }
}

struct MessageRow: View, Equatable {
    let agentId: String
    let message: ChatMessage
    let name: String
    let worker: String
    @Environment(AppModel.self) private var model
    @State private var fullText: String?
    @State private var expanded = false
    @State private var loadingFull = false

    static func == (lhs: MessageRow, rhs: MessageRow) -> Bool {
        lhs.message == rhs.message && lhs.agentId == rhs.agentId && lhs.name == rhs.name
    }

    private var isUser: Bool { message.role == "user" }
    private var images: [EventImage] { (message.images ?? []).filter { $0.status == "available" } }
    private var text: String { fullText ?? message.text ?? "" }
    /// Pasted context and tool output from the transcript can be tens of thousands of characters.
    private var collapsible: Bool { text.count > 1800 || message.truncated == true }

    var body: some View {
        if isUser {
            HStack {
                Spacer(minLength: 48)
                VStack(alignment: .trailing, spacing: Tokens.Space.s) {
                    bodyText
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Tokens.userBubble, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    imageRow
                }
            }
            .padding(.vertical, 6)
            .messageActions(text: text, title: "Message")
        } else {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                bodyText
                imageRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Tokens.Space.s)
            .messageActions(text: text, title: "\(name)'s reply")
        }
    }

    @ViewBuilder private var bodyText: some View {
        if collapsible && !expanded {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(text.prefix(600)) + "…")
                    .font(TypeScale.body)
                    .foregroundStyle(Tokens.textPrimary)
                Button {
                    Task { await expand() }
                } label: {
                    HStack(spacing: 4) {
                        if loadingFull { ProgressView().controlSize(.mini) }
                        Text("Show full message (\((message.fullLength ?? text.count).formatted()) characters)")
                    }
                    .font(TypeScale.captionMedium)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Tokens.accent)
            }
        } else {
            MarkdownText(text: text)
        }
    }

    private func expand() async {
        if message.truncated == true, fullText == nil {
            loadingFull = true
            fullText = await model.fullMessage(agentId: agentId, id: message.id)
            loadingFull = false
        }
        expanded = true
    }

    @ViewBuilder private var imageRow: some View {
        if !images.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Tokens.Space.s) {
                    ForEach(images) { image in
                        RemoteImage(agentId: agentId, image: image)
                    }
                }
            }
        }
    }
}

struct ActivityGroupRow: View {
    let agentId: String
    let group: ActivityGroup
    let onSelectEvent: (LiveEvent) -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: Tokens.Space.s) {
                    statusGlyph
                    Text(group.summary)
                        .font(TypeScale.captionMedium)
                        .foregroundStyle(Tokens.textSecondary)
                    Spacer(minLength: Tokens.Space.s)
                    RelativeTimeText(iso: group.lastTime)
                        .font(TypeScale.caption)
                        .foregroundStyle(Tokens.textTertiary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Tokens.textTertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(group.summary). \(expanded ? "Collapse" : "Expand")")

            if expanded {
                HStack(alignment: .top, spacing: Tokens.Space.m) {
                    Rectangle().fill(Tokens.hairline).frame(width: 1)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(group.events) { event in
                            ActivityEventRow(agentId: agentId, event: event) { onSelectEvent(event) }
                        }
                    }
                }
                .padding(.bottom, Tokens.Space.s)
            }
            if !expanded && !group.availableImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Tokens.Space.s) {
                        ForEach(group.availableImages.prefix(6)) { image in
                            RemoteImage(agentId: agentId, image: image, side: 64)
                        }
                    }
                }
                .padding(.bottom, Tokens.Space.xs)
            }
        }
    }

    @ViewBuilder private var statusGlyph: some View {
        if group.running {
            ProgressView().controlSize(.mini).tint(Tokens.working).frame(width: 14)
        } else if group.failed {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 11, weight: .semibold)).foregroundStyle(Tokens.failure).frame(width: 14)
        } else {
            Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Tokens.textTertiary).frame(width: 14)
        }
    }
}

struct ActivityEventRow: View {
    let agentId: String
    let event: LiveEvent
    let onTap: () -> Void

    private var images: [EventImage] { (event.images ?? []).filter { $0.status == "available" } }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Button(action: onTap) {
                HStack(spacing: Tokens.Space.s) {
                    Image(systemName: EventStyle.symbol(for: event))
                        .font(.system(size: 11))
                        .foregroundStyle(EventStyle.color(for: event))
                        .frame(width: 16)
                    Text(ConversationBuilder.displayTitle(for: event))
                        .font(TypeScale.caption)
                        .foregroundStyle(Tokens.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: Tokens.Space.xs)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Tokens.textTertiary)
                }
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(event.title)
            if !images.isEmpty {
                HStack(spacing: Tokens.Space.s) {
                    ForEach(images) { image in RemoteImage(agentId: agentId, image: image) }
                }
                .padding(.bottom, Tokens.Space.xs)
            }
        }
    }
}

struct QueueSection: View {
    let agentId: String
    let store: ConversationStore
    let manage: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let failures = store.failures
        let pending = store.pendingQueue
        if !failures.isEmpty {
            Button(action: manage) {
                Label("\(failures.count) delivery issue\(failures.count == 1 ? "" : "s") · Manage", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .frame(minHeight: 44)
            }
            .tint(Tokens.failure)
        }
        if !pending.isEmpty {
            VStack(alignment: .trailing, spacing: Tokens.Space.s) {
                ForEach(pending) { item in
                    HStack {
                        Spacer(minLength: 48)
                        VStack(alignment: .trailing, spacing: Tokens.Space.xs) {
                            Text(item.text ?? "")
                                .font(TypeScale.body)
                                .foregroundStyle(Tokens.textPrimary)
                                .lineLimit(8)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Tokens.userBubble.opacity(0.6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            HStack(spacing: Tokens.Space.m) {
                                Label(label(item), systemImage: "clock")
                                    .font(TypeScale.caption)
                                    .foregroundStyle(Tokens.textTertiary)
                                    .lineLimit(2)
                                if ["queued", "waiting_busy"].contains(item.state ?? ""), model.team.agent(agentId)?.steerable == true {
                                    Button("Steer now") { Task { await model.steerQueued(id: item.id, agentId: agentId) } }
                                        .font(TypeScale.captionMedium)
                                        .foregroundStyle(Tokens.accent)
                                        .fixedSize()
                                }
                                if ["queued", "waiting_busy", "waiting_connection"].contains(item.state ?? "") {
                                    Button("Cancel") { Task { await model.cancelQueued(id: item.id, agentId: agentId) } }
                                        .font(TypeScale.captionMedium)
                                        .foregroundStyle(Tokens.textSecondary)
                                        .fixedSize()
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, Tokens.Space.xs)
        }
    }

    private func label(_ item: ChatMessage) -> String {
        switch item.state {
        case "queued": return "Queued"
        case "steered": return "Steered into the current turn"
        case "waiting_busy": return item.error?.isEmpty == false ? item.error! : "Waiting for the current turn"
        case "waiting_connection": return "Waiting for the runner"
        case "sending": return "Sending…"
        default: return item.state ?? "Pending"
        }
    }
}

struct LiveTextRow: View {
    let text: String
    let worker: String

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            MarkdownText(text: text)
            ActivityLine(text: "Writing…", color: AgentStyle.color(worker))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Tokens.Space.s)
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
        if event.status == "failed" || event.kind == "error" { return Tokens.failure }
        if event.status == "running" { return Tokens.working }
        return Tokens.textSecondary
    }
}

struct EventDetailSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let agentId: String
    let event: LiveEvent
    @State private var detail: EventDetail?

    private var images: [EventImage] {
        ((detail?.images ?? event.images) ?? []).filter { $0.status == "available" }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.m) {
                    VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                        Text(ConversationBuilder.displayTitle(for: event))
                            .font(TypeScale.title)
                            .foregroundStyle(Tokens.textPrimary)
                        HStack(spacing: Tokens.Space.s) {
                            Text(event.kind)
                            if let status = event.status { Text(status) }
                            if let time = TimeFormat.date(event.time) {
                                Text(time.formatted(date: .abbreviated, time: .standard))
                            }
                        }
                        .font(TypeScale.caption)
                        .foregroundStyle(Tokens.textSecondary)
                    }
                    if !images.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Tokens.Space.s) {
                                ForEach(images) { image in RemoteImage(agentId: agentId, image: image, side: 120) }
                            }
                        }
                    }
                    let raw = detail?.detail ?? event.detailPreview ?? ""
                    if raw.isEmpty && detail == nil {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, Tokens.Space.l)
                    } else {
                        let sections = OutputSections.build(raw)
                        ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                                Text(section.label)
                                    .font(TypeScale.captionMedium)
                                    .foregroundStyle(Tokens.textTertiary)
                                CodeText(text: section.text, collapsible: true, tint: section.kind == .error ? Tokens.failure : nil)
                            }
                        }
                    }
                }
                .padding(Tokens.Space.m)
            }
            .background(Tokens.background)
            .navigationTitle("Activity detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .task { detail = await model.detail(for: event, agentId: agentId) }
        }
    }
}
