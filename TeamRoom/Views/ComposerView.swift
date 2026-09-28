import SwiftUI

struct ComposerView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 6) {
            if model.selectedAgent?.canStop == true {
                Button(role: .destructive) {
                    Task { await model.stopTurn() }
                } label: {
                    Label("Stop this turn", systemImage: "stop.circle")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField(placeholder, text: draft, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($focused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 21))
                Button {
                    Task { await model.send(draft.wrappedValue) }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline)
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.glassProminent)
                .clipShape(Circle())
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.55)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 6)
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
