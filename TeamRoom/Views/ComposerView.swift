import SwiftUI

struct ComposerView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: Tokens.Space.s) {
            if model.selectedAgent?.canStop == true {
                Button(role: .destructive) {
                    Task { await model.stopTurn() }
                } label: {
                    Label("Stop this turn", systemImage: "stop.circle")
                        .font(TypeScale.captionMedium)
                }
                .buttonStyle(.bordered)
                .tint(Tokens.failure)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            HStack(alignment: .bottom, spacing: Tokens.Space.s) {
                TextField(placeholder, text: draft, axis: .vertical)
                    .font(TypeScale.body)
                    .lineLimit(1...6)
                    .focused($focused)
                    .padding(.horizontal, Tokens.Space.m)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
                Button {
                    Task { await model.send(draft.wrappedValue) }
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
            }
        }
        .padding(.horizontal, Tokens.Space.m)
        .padding(.top, Tokens.Space.s)
        .padding(.bottom, Tokens.Space.s)
    }

    private var draft: Binding<String> {
        Binding(
            get: { model.selectedId.isEmpty ? "" : (model.drafts[model.selectedId] ?? "") },
            set: { value in
                guard !model.selectedId.isEmpty else { return }
                model.drafts[model.selectedId] = value
            }
        )
    }

    private var placeholder: String {
        if let label = model.selectedAgent?.label { return "Message \(label)" }
        return "Select a teammate"
    }

    private var canSend: Bool {
        !draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.sending
            && model.selectedAgent != nil
    }
}
