import SwiftUI

/// Pending decision from a teammate: a question, command/file approval, or permission request.
struct DecisionCard: View {
    @Environment(AppModel.self) private var model
    let agentId: String
    let prompt: AgentPrompt
    var extraCount: Int = 0

    @State private var selections: [String: String] = [:]
    @State private var otherText: [String: String] = [:]
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            header
            switch prompt.kind {
            case "question":
                questionBody
            case "command", "file", "permissions":
                approvalBody
            default:
                Text(prompt.detail ?? "This request cannot be displayed yet.")
                    .font(TypeScale.caption)
                    .foregroundStyle(Tokens.textSecondary)
            }
            if extraCount > 0 {
                Text("+\(extraCount) more waiting")
                    .font(TypeScale.caption)
                    .foregroundStyle(Tokens.textTertiary)
            }
        }
        .padding(Tokens.Space.m)
        .background(Tokens.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.l, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.l, style: .continuous)
                .stroke(Tokens.accent.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Tokens.Space.s) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Tokens.accent)
                .frame(width: 26, height: 26)
                .background(Tokens.accentSoft, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(prompt.title ?? "Waiting for you")
                    .font(TypeScale.subhead)
                    .foregroundStyle(Tokens.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(TypeScale.caption)
                    .foregroundStyle(Tokens.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if busy {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var icon: String {
        switch prompt.kind {
        case "question": return "questionmark.bubble"
        case "command": return "terminal"
        case "file": return "doc.text"
        case "permissions": return "lock.shield"
        default: return "hand.raised"
        }
    }

    private var subtitle: String {
        switch prompt.kind {
        case "question": return "Answer to let the teammate continue"
        case "command": return "Nothing runs until you approve"
        case "file": return "File changes are blocked until you approve"
        case "permissions": return "Wider sandbox access requested"
        default: return "Input requested"
        }
    }

    // MARK: - Questions

    @ViewBuilder private var questionBody: some View {
        let questions = prompt.questions ?? []
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            ForEach(questions) { question in
                VStack(alignment: .leading, spacing: Tokens.Space.s) {
                    if let header = question.header, !header.isEmpty {
                        Text(header.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Tokens.textTertiary)
                    }
                    Text(question.question)
                        .font(TypeScale.body)
                        .foregroundStyle(Tokens.textPrimary)
                    ForEach(question.options ?? []) { option in
                        optionRow(question: question, option: option)
                    }
                    if question.isOther == true {
                        otherRow(question: question)
                    }
                }
            }
            HStack(spacing: Tokens.Space.m) {
                Button("Send answer") { submitAnswers() }
                    .font(TypeScale.captionMedium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Tokens.Space.m)
                    .padding(.vertical, 9)
                    .background(canSubmit ? Tokens.accent : Tokens.textTertiary.opacity(0.4), in: Capsule())
                    .disabled(!canSubmit || busy)
                Button("Skip") { respond(PromptAnswer(decline: true)) }
                    .font(TypeScale.captionMedium)
                    .foregroundStyle(Tokens.textSecondary)
                    .disabled(busy)
            }
        }
    }

    private func optionRow(question: PromptQuestion, option: PromptOption) -> some View {
        let selected = selections[question.id] == option.label && (otherText[question.id] ?? "").isEmpty
        return Button {
            selections[question.id] = option.label
            otherText[question.id] = ""
        } label: {
            HStack(alignment: .top, spacing: Tokens.Space.s) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(selected ? Tokens.accent : Tokens.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(TypeScale.subhead)
                        .foregroundStyle(Tokens.textPrimary)
                    if let description = option.description, !description.isEmpty {
                        Text(description)
                            .font(TypeScale.caption)
                            .foregroundStyle(Tokens.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Tokens.Space.s)
            .background(selected ? Tokens.accentSoft : Tokens.surfaceAlt, in: RoundedRectangle(cornerRadius: Tokens.Radius.s, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func otherRow(question: PromptQuestion) -> some View {
        let active = !(otherText[question.id] ?? "").isEmpty
        let text = Binding(
            get: { otherText[question.id] ?? "" },
            set: { value in
                otherText[question.id] = value
                if !value.isEmpty { selections[question.id] = nil }
            }
        )
        HStack(spacing: Tokens.Space.s) {
            Image(systemName: active ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 15))
                .foregroundStyle(active ? Tokens.accent : Tokens.textTertiary)
            if question.isSecret == true {
                SecureField("Something else…", text: text)
                    .font(TypeScale.body)
            } else {
                TextField("Something else…", text: text)
                    .font(TypeScale.body)
            }
            Spacer(minLength: 0)
        }
        .padding(Tokens.Space.s)
        .background(active ? Tokens.accentSoft : Tokens.surfaceAlt, in: RoundedRectangle(cornerRadius: Tokens.Radius.s, style: .continuous))
    }

    private var canSubmit: Bool {
        let questions = prompt.questions ?? []
        guard !questions.isEmpty else { return false }
        return questions.allSatisfy { question in
            if let selection = selections[question.id], !selection.isEmpty { return true }
            return !(otherText[question.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func submitAnswers() {
        var answers: [String: PromptAnswerValue] = [:]
        for question in prompt.questions ?? [] {
            if let selection = selections[question.id], !selection.isEmpty {
                answers[question.id] = PromptAnswerValue(answers: [selection])
            } else if let other = otherText[question.id] {
                let trimmed = other.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    answers[question.id] = PromptAnswerValue(answers: [trimmed])
                }
            }
        }
        respond(PromptAnswer(answers: answers))
    }

    // MARK: - Approvals

    @ViewBuilder private var approvalBody: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            if let command = prompt.command, !command.isEmpty {
                CodeText(text: command)
            }
            if let detail = prompt.detail, !detail.isEmpty {
                CodeText(text: detail)
            }
            if let cwd = prompt.cwd, !cwd.isEmpty {
                Text(cwd)
                    .font(TypeScale.monoSmall)
                    .foregroundStyle(Tokens.textTertiary)
                    .lineLimit(1)
            }
            if let reason = prompt.reason, !reason.isEmpty {
                Text(reason)
                    .font(TypeScale.caption)
                    .foregroundStyle(Tokens.textSecondary)
            }
            VStack(spacing: Tokens.Space.s) {
                if prompt.kind == "permissions" {
                    actionButton("Allow once", fill: true) { respond(PromptAnswer(scope: "turn")) }
                    actionButton("Allow this session", fill: false) { respond(PromptAnswer(scope: "session")) }
                } else {
                    actionButton("Approve", fill: true) { respond(PromptAnswer(decision: "accept")) }
                    if prompt.allowSession == true {
                        actionButton("Approve for session", fill: false) { respond(PromptAnswer(decision: "acceptForSession")) }
                    }
                }
                actionButton("Deny", fill: false, danger: true) {
                    if prompt.kind == "permissions" {
                        respond(PromptAnswer(deny: true))
                    } else {
                        respond(PromptAnswer(decision: "decline"))
                    }
                }
            }
        }
    }

    private func actionButton(_ title: String, fill: Bool, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(TypeScale.captionMedium)
                .foregroundStyle(fill ? .white : (danger ? Tokens.failure : Tokens.textPrimary))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(fill ? Tokens.accent : Tokens.surfaceAlt, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private func respond(_ answer: PromptAnswer) {
        busy = true
        Task { @MainActor in
            await model.respond(agentId: agentId, to: prompt, answer: answer)
            busy = false
        }
    }
}
