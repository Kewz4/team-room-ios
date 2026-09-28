import SwiftUI

struct PairView: View {
    @Environment(AppModel.self) private var model
    @State private var input = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.l) {
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    Text("Team Room")
                        .font(TypeScale.screenTitle)
                        .foregroundStyle(Tokens.textPrimary)
                    Text("Your private console for the local AI teammates, now native on iPhone.")
                        .font(TypeScale.body)
                        .foregroundStyle(Tokens.textSecondary)
                }

                VStack(alignment: .leading, spacing: Tokens.Space.s) {
                    step(1, "On the PC, open Team Room → Connection settings → Create device link.")
                    step(2, "Copy the link and paste it below within 30 minutes. Each link works once.")
                    step(3, "The session is kept in your iPhone Keychain; nothing is stored in the repo.")
                }

                VStack(alignment: .leading, spacing: Tokens.Space.s) {
                    TextField("https://….trycloudflare.com/#pair=…", text: $input, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(TypeScale.mono)
                        .padding(Tokens.Space.m)
                        .background(Tokens.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.m, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Tokens.Radius.m, style: .continuous)
                                .stroke(Tokens.hairline, lineWidth: 0.5)
                        )

                    Button {
                        Task { await model.pair(input) }
                    } label: {
                        HStack {
                            Spacer()
                            if model.pairingBusy {
                                ProgressView().controlSize(.small)
                            }
                            Text("Connect").font(TypeScale.subhead)
                            Spacer()
                        }
                        .frame(height: 44)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Tokens.accent)
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.pairingBusy)
                }

                if let error = model.pairingError {
                    Text(error)
                        .font(TypeScale.caption)
                        .foregroundStyle(Tokens.failure)
                }
            }
            .padding(Tokens.Space.l)
        }
        .background(Tokens.background)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
            Text("\(number)")
                .font(TypeScale.captionMedium)
                .foregroundStyle(Tokens.accent)
                .frame(width: 20, height: 20)
                .background(Tokens.accentSoft, in: Circle())
            Text(text)
                .font(TypeScale.caption)
                .foregroundStyle(Tokens.textSecondary)
        }
    }
}
