import SwiftUI

/// The main team chat: ask anything about the team; a coordinator answers (Polaris, Sage, Vega, Orion or Atlas,
/// whoever is free), with the reason shown when the question was handed over. Each coordinator answers from a
/// dedicated desk conversation on its own account, fed a live team digest, so a question never waits behind their work.
struct TeamChatView: View {
    @Environment(AppModel.self) private var model
    @State private var focus: String?
    @State private var addressee: String?
    @FocusState private var composerFocused: Bool

    private let suggestions = [
        "What's everyone working on right now?",
        "What's blocked, and why?",
        "What do you need from me?",
        "Summarize today's progress",
        "How close is the Unova arc to playable?",
        "What changed since yesterday?"
    ]

    var body: some View {
        NavigationStack {
            ChatScroll(followKey: followKey, focus: $focus) {
                if model.room.messages.isEmpty {
                    emptyState
                }
                ForEach(model.room.messages) { message in
                    RoomMessageRow(message: message, coordinators: model.room.coordinators)
                        .id(message.id)
                }
            }
            .background(Tokens.background)
            .safeAreaInset(edge: .top, spacing: 0) { ConnectionBanner() }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SettingsToolbarItem(router: model.router)
                ToolbarItem(placement: .principal) { header }
                // 1.2: while typing, the hide-keyboard button takes the More menu's place, so the five coordinator
                // names keep their room in the title.
                ToolbarItem(placement: .topBarTrailing) {
                    if composerFocused {
                        HideKeyboardButton { composerFocused = false }
                    } else {
                        Menu {
                            Button { model.router.tab = .board } label: { Label("Project board", systemImage: "chart.bar.doc.horizontal") }
                            Button { model.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        } label: { Image(systemName: "ellipsis") }
                        .accessibilityLabel("More")
                    }
                }
            }
            .onAppear {
                model.markRoomSeen()
                if let target = model.router.focusRoomMessage { focus = target; model.router.focusRoomMessage = nil }
            }
            .onChange(of: model.room.messages.count) { _, _ in model.markRoomSeen() }
            .onChange(of: model.router.focusRoomMessage) { _, target in
                guard let target else { return }
                focus = target
                model.router.focusRoomMessage = nil
            }
            .refreshable { await model.refreshRoom() }
        }
    }

    private var followKey: Int {
        let last = model.room.messages.last
        return model.room.messages.count &* 31 &+ (last?.text?.count ?? 0) &+ (last?.state?.hashValue ?? 0)
    }

    private var header: some View {
        VStack(spacing: 1) {
            Text("Team")
                .font(.headline)
            HStack(spacing: 6) {
                ForEach(model.room.coordinators.isEmpty ? defaultCoordinators : model.room.coordinators) { coordinator in
                    HStack(spacing: 3) {
                        Circle()
                            .fill(coordinator.available == false ? Tokens.textTertiary : coordinator.answering == true ? Tokens.working : Tokens.idle)
                            .frame(width: 6, height: 6)
                        Text(coordinator.label)
                            .font(.caption2)
                            .foregroundStyle(Tokens.textSecondary)
                            // 1.1.2: the coordinators (five since 1.2) share the title row; shrink a name rather than wrap it letter by letter.
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(coordinator.label) \(coordinator.available == false ? "unavailable" : coordinator.answering == true ? "answering" : "available")")
                }
            }
        }
    }

    /// The room's live roster (1.1.2: the empty chat no longer hard-codes three coordinators).
    private var roster: [Coordinator] { model.room.coordinators.isEmpty ? defaultCoordinators : model.room.coordinators }

    /// "Polaris, Sage, Vega, Orion or Atlas".
    private func orList(_ items: [String]) -> String {
        guard let last = items.last else { return "A coordinator" }
        return items.count == 1 ? last : items.dropLast().joined(separator: ", ") + " or " + last
    }

    /// Only until the server's roster arrives (1.2, Kewz 2026-10-04: Polaris, Sage, Vega, Orion and Atlas; Nimbus retired).
    private var defaultCoordinators: [Coordinator] {
        [Coordinator(name: "polaris", label: "Polaris"), Coordinator(name: "sage", label: "Sage"), Coordinator(name: "vega", label: "Vega"),
         Coordinator(name: "orion", label: "Orion"), Coordinator(name: "atlas", label: "Atlas")]
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: -8) {
                    ForEach(roster) { coordinator in
                        AgentAvatar(worker: coordinator.name, size: 34)
                    }
                }
                Text("Ask the team anything")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Tokens.textPrimary)
                Text("\(orList(roster.map(\.label))) answers — whoever is free — using the live state of every teammate, the plan and the board. Start with \(orList(roster.map { "@" + $0.label })) to pick one.")
                    .font(TypeScale.footnote)
                    .foregroundStyle(Tokens.textSecondary)
            }
            FlowLayout(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        Task { await model.ask(suggestion, mention: addressee) }
                    } label: {
                        Text(suggestion)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Tokens.surface, in: Capsule())
                            .overlay(Capsule().stroke(Tokens.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("suggestion")
                }
            }
        }
        .padding(.vertical, Tokens.Space.l)
    }

    private var composer: some View {
        @Bindable var bindable = model
        let answering = model.room.answering
        return VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: Tokens.Space.s) {
                Menu {
                    Button { addressee = nil } label: { Label("Whoever is free", systemImage: addressee == nil ? "checkmark" : "person.2") }
                    // 1.2: one entry per coordinator in the server's roster (1.1.2 hard-coded Polaris, Nova and Atlas).
                    ForEach(roster) { coordinator in
                        Button { addressee = coordinator.name } label: {
                            Label(coordinator.label, systemImage: addressee == coordinator.name ? "checkmark" : "person")
                        }
                    }
                } label: {
                    Group {
                        if let addressee {
                            AgentAvatar(worker: addressee, size: 30)
                        } else {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Tokens.textSecondary)
                                .frame(width: 30, height: 30)
                        }
                    }
                    .frame(width: 42, height: 42)
                    .glassEffect(.regular, in: Circle())
                }
                .accessibilityLabel(addressee == nil ? "Ask whoever is free" : "Ask \(AgentStyle.displayName(addressee))")

                TextField(placeholder, text: $bindable.roomDraft, axis: .vertical)
                    .font(TypeScale.body)
                    .lineLimit(1...6)
                    .focused($composerFocused)
                    .padding(.horizontal, Tokens.Space.m)
                    .padding(.vertical, 11)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .accessibilityIdentifier("team-composer")

                if let answering {
                    Button {
                        Task { await model.stopAnswer(answering.id) }
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Tokens.textPrimary)
                    .clipShape(Circle())
                    .accessibilityLabel("Stop answer")
                } else {
                    Button {
                        let text = model.roomDraft
                        Task { await model.ask(text, mention: addressee) }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Tokens.accent)
                    .clipShape(Circle())
                    .disabled(!canSend)
                    .opacity(canSend ? 1 : 0.5)
                    .accessibilityLabel("Send question")
                    .accessibilityIdentifier("team-send")
                }
            }
            .padding(.horizontal, Tokens.Space.m)
            .padding(.top, Tokens.Space.s)
            .padding(.bottom, Tokens.Space.s)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: model.room.messages.count)
    }

    private var placeholder: String {
        if let addressee { return "Ask \(AgentStyle.displayName(addressee))…" }
        return "Ask the team…"
    }

    private var canSend: Bool {
        !model.roomDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.room.sending
    }
}

/// One message in the team chat: Kewz's question on the right, a coordinator's answer on the left.
struct RoomMessageRow: View, Equatable {
    let message: RoomMessage
    let coordinators: [Coordinator]
    @Environment(AppModel.self) private var model
    @State private var showClaim = false

    static func == (lhs: RoomMessageRow, rhs: RoomMessageRow) -> Bool {
        lhs.message == rhs.message && lhs.coordinators == rhs.coordinators
    }

    var body: some View {
        if message.isUser {
            HStack {
                Spacer(minLength: 48)
                Text(MarkdownBlocks.inline(message.text ?? ""))
                    .font(TypeScale.body)
                    .foregroundStyle(Tokens.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Tokens.userBubble, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .opacity(message.state == "sending" ? 0.6 : 1)
                    .messageActions(text: message.text ?? "", title: "Your question")
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("You: \(message.text ?? "")")
        } else {
            answer
        }
    }

    private var responder: String { message.responder ?? message.claim?.responder ?? "coordinator" }

    private var answer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AgentAvatar(worker: responder, size: 26, state: message.isInProgress ? "working" : "idle", showRing: message.isInProgress)
                Text(AgentStyle.displayName(responder))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AgentStyle.color(responder))
                if let time = elapsed {
                    Text(time)
                        .font(TypeScale.caption)
                        .foregroundStyle(Tokens.textTertiary)
                }
                Spacer(minLength: 0)
                if message.claimWorthShowing || (message.attempts ?? []).isEmpty == false {
                    Button {
                        showClaim.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Tokens.textTertiary)
                            .frame(width: 32, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Why \(AgentStyle.displayName(responder)) answered")
                }
            }
            if showClaim || (message.claimWorthShowing && message.isInProgress), let reason = message.claim?.reason {
                Text(reason)
                    .font(TypeScale.caption)
                    .foregroundStyle(Tokens.textSecondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Tokens.surfaceAlt, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            if let text = message.text, !text.isEmpty {
                MarkdownText(text: text)
                    .messageActions(text: text, title: "\(AgentStyle.displayName(responder))'s answer")
            }
            if message.isInProgress {
                ActivityLine(text: message.activity ?? (message.state == "queued" ? "Waiting for a coordinator…" : "\(AgentStyle.displayName(responder)) is thinking…"),
                             color: AgentStyle.color(responder))
            }
            if message.isFailure {
                VStack(alignment: .leading, spacing: 6) {
                    Label(failureTitle, systemImage: message.state == "stopped" ? "stop.circle" : "exclamationmark.triangle")
                        .font(TypeScale.captionMedium)
                        .foregroundStyle(message.state == "stopped" ? Tokens.textSecondary : Tokens.failure)
                    if let error = message.error, !error.isEmpty {
                        Text(error)
                            .font(TypeScale.caption)
                            .foregroundStyle(Tokens.textSecondary)
                    }
                    Button {
                        Task { await model.retryAnswer(message.id) }
                    } label: {
                        Label("Ask again", systemImage: "arrow.clockwise")
                            .font(TypeScale.captionMedium)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sensoryFeedback(.success, trigger: message.state) { old, new in old == "answering" && new == "answered" }
    }

    private var failureTitle: String {
        switch message.state {
        case "stopped": return "Stopped"
        case "interrupted": return "Interrupted by a restart"
        default: return "No answer"
        }
    }

    private var elapsed: String? {
        guard let start = TimeFormat.date(message.startedAt ?? message.createdAt) else { return nil }
        if message.state == "answered", let end = TimeFormat.date(message.completedAt) {
            let seconds = Int(end.timeIntervalSince(start).rounded())
            return seconds < 90 ? "· \(seconds)s" : "· \(seconds / 60) min"
        }
        return message.isInProgress ? nil : "· " + TimeFormat.relative(start)
    }
}

/// Wrapping layout for suggestion chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
