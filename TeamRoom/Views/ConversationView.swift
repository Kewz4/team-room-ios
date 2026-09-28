import SwiftUI

struct ConversationView: View {
    @Environment(AppModel.self) private var model
    @Binding var selectedEvent: LiveEvent?
    @State private var atBottom = true

    private let bottomID = "conversation-bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if model.items.isEmpty {
                        emptyState
                    }
                    ForEach(model.items) { item in
                        switch item {
                        case .message(let message):
                            MessageRow(agentId: model.selectedId, message: message)
                        case .activity(let group):
                            ActivityGroupRow(agentId: model.selectedId, group: group) { event in
                                selectedEvent = event
                            }
                        }
                    }
                    QueueSection(agentId: model.selectedId)
                    if let live = model.selectedAgent?.liveText, !live.isEmpty {
                        LiveTextRow(text: live)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(bottomID)
                }
                .padding(.horizontal, Tokens.Space.m)
                .padding(.top, Tokens.Space.s)
                .padding(.bottom, Tokens.Space.m)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height < 160
            } action: { _, value in
                atBottom = value
            }
            .onChange(of: scrollTick) { _, _ in
                guard atBottom else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !atBottom {
                    Button {
                        withAnimation(.snappy(duration: 0.25)) {
                            proxy.scrollTo(bottomID, anchor: .bottom)
                        }
                        atBottom = true
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .padding(.trailing, Tokens.Space.m)
                    .padding(.bottom, Tokens.Space.s)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .accessibilityLabel("Scroll to latest")
                }
            }
            .animation(.snappy(duration: 0.2), value: atBottom)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text(model.selectedAgent == nil ? "Pick a teammate" : "No conversation yet")
                .font(TypeScale.subhead)
                .foregroundStyle(Tokens.textSecondary)
            if let label = model.selectedAgent?.label {
                Text("Send the first message to \(label) from the composer below.")
                    .font(TypeScale.caption)
                    .foregroundStyle(Tokens.textTertiary)
            }
        }
        .padding(.vertical, Tokens.Space.l)
    }

    private var scrollTick: String {
        guard let agent = model.selectedAgent else { return model.selectedId }
        let messages = agent.messages?.count ?? 0
        let live = agent.liveText?.count ?? 0
        let queue = agent.queue?.count ?? 0
        return "\(model.selectedId)-\(messages)-\(live)-\(queue)"
    }
}

struct MessageRow: View {
    let agentId: String
    let message: ChatMessage

    private var isUser: Bool { message.role == "user" }
    private var images: [EventImage] { (message.images ?? []).filter { $0.status == "available" } }

    var body: some View {
        if isUser {
            HStack {
                Spacer(minLength: 56)
                VStack(alignment: .trailing, spacing: Tokens.Space.s) {
                    MarkdownText(text: message.text ?? "")
                        .padding(.horizontal, Tokens.Space.m)
                        .padding(.vertical, 10)
                        .background(Tokens.accentSoft, in: RoundedRectangle(cornerRadius: Tokens.Radius.l, style: .continuous))
                    imageRow
                }
            }
            .padding(.vertical, Tokens.Space.xs)
        } else {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                MarkdownText(text: message.text ?? "")
                imageRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Tokens.Space.s)
        }
    }

    @ViewBuilder private var imageRow: some View {
        if !images.isEmpty {
            HStack(spacing: Tokens.Space.s) {
                ForEach(images) { image in
                    RemoteImage(agentId: agentId, image: image)
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
                withAnimation(.snappy(duration: 0.2)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: Tokens.Space.s) {
                    statusGlyph
                    Text(group.summary)
                        .font(TypeScale.captionMedium)
                        .foregroundStyle(Tokens.textSecondary)
                    Spacer(minLength: Tokens.Space.s)
                    Text(TimeFormat.relative(group.lastTime))
                        .font(TypeScale.caption)
                        .foregroundStyle(Tokens.textTertiary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Tokens.textTertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                HStack(alignment: .top, spacing: Tokens.Space.m) {
                    Rectangle()
                        .fill(Tokens.hairline)
                        .frame(width: 1)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(group.events) { event in
                            ActivityEventRow(agentId: agentId, event: event) {
                                onSelectEvent(event)
                            }
                        }
                    }
                }
                .padding(.bottom, Tokens.Space.s)
            }
        }
    }

    @ViewBuilder private var statusGlyph: some View {
        if group.running {
            ProgressView()
                .controlSize(.mini)
                .tint(Tokens.working)
                .frame(width: 14)
        } else if group.failed {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Tokens.failure)
                .frame(width: 14)
        } else {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Tokens.textTertiary)
                .frame(width: 14)
        }
    }
}

struct ActivityEventRow: View {
    let agentId: String
    let event: LiveEvent
    let onTap: () -> Void

    private var images: [EventImage] {
        (event.images ?? []).filter { $0.status == "available" }
    }

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
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(event.title)

            if !images.isEmpty {
                HStack(spacing: Tokens.Space.s) {
                    ForEach(images) { image in
                        RemoteImage(agentId: agentId, image: image)
                    }
                }
                .padding(.bottom, Tokens.Space.xs)
            }
        }
    }
}

struct QueueSection: View {
    @Environment(AppModel.self) private var model
    let agentId: String

    var body: some View {
        let items = (model.selectedAgent?.queue ?? []).filter { ($0.text ?? "").isEmpty == false }
        if !items.isEmpty {
            VStack(alignment: .trailing, spacing: Tokens.Space.s) {
                ForEach(items) { item in
                    HStack {
                        Spacer(minLength: 56)
                        VStack(alignment: .trailing, spacing: Tokens.Space.xs) {
                            Text(item.text ?? "")
                                .font(TypeScale.body)
                                .foregroundStyle(Tokens.textPrimary)
                                .padding(.horizontal, Tokens.Space.m)
                                .padding(.vertical, 10)
                                .background(Tokens.accentSoft.opacity(0.65), in: RoundedRectangle(cornerRadius: Tokens.Radius.l, style: .continuous))
                            HStack(spacing: Tokens.Space.m) {
                                Text(queueLabel(item))
                                    .font(TypeScale.caption)
                                    .foregroundStyle(Tokens.textTertiary)
                                if canCancel(item) {
                                    Button("Cancel") {
                                        Task { await model.cancelQueued(id: item.id) }
                                    }
                                    .font(TypeScale.captionMedium)
                                    .foregroundStyle(Tokens.textSecondary)
                                }
                                if canRetry(item) {
                                    Button("Retry") {
                                        Task { await model.retryMessage(id: item.id) }
                                    }
                                    .font(TypeScale.captionMedium)
                                    .foregroundStyle(Tokens.accent)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, Tokens.Space.xs)
        }
    }

    private func queueLabel(_ item: ChatMessage) -> String {
        switch item.state {
        case "queued": return "Queued"
        case "waiting_busy": return "Waiting for the current turn"
        case "waiting_connection": return "Waiting for the runner"
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

struct LiveTextRow: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            MarkdownText(text: text)
            BlinkingDot()
                .foregroundStyle(Tokens.working)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Tokens.Space.s)
    }
}

struct BlinkingDot: View {
    @State private var dim = false

    var body: some View {
        Circle()
            .frame(width: 6, height: 6)
            .opacity(dim ? 0.25 : 1)
            .animation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true), value: dim)
            .onAppear { dim = true }
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
                                ForEach(images) { image in
                                    RemoteImage(agentId: agentId, image: image, side: 120)
                                }
                            }
                        }
                    }

                    let raw = detail?.detail ?? event.detailPreview ?? ""
                    if raw.isEmpty && detail == nil {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Tokens.Space.l)
                    } else {
                        ForEach(OutputSections.build(raw)) { section in
                            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                                Text(section.label)
                                    .font(TypeScale.captionMedium)
                                    .foregroundStyle(Tokens.textTertiary)
                                CodeText(
                                    text: section.text,
                                    collapsible: true,
                                    tint: section.kind == .error ? Tokens.failure : nil
                                )
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { detail = await model.detail(for: event) }
        }
    }
}
