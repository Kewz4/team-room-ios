import SwiftUI
import UIKit

struct PairView: View {
    @Environment(AppModel.self) private var model
    @State private var input = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.l) {
                VStack(alignment: .leading, spacing: Tokens.Space.s) {
                    HStack(spacing: -10) {
                        ForEach(["nova", "atlas", "scout", "flint", "sage"], id: \.self) { worker in
                            AgentAvatar(worker: worker, size: 40)
                                .overlay(Circle().stroke(Tokens.background, lineWidth: 2))
                        }
                    }
                    Text("Team Room")
                        .font(TypeScale.screenTitle)
                        .foregroundStyle(Tokens.textPrimary)
                    Text("Your AI team, from anywhere: ask the team, follow each teammate, and see the whole project's progress.")
                        .font(TypeScale.body)
                        .foregroundStyle(Tokens.textSecondary)
                }

                VStack(alignment: .leading, spacing: Tokens.Space.s) {
                    step(1, "On the PC, open Team Room → Connection settings → Create device link.")
                    step(2, "Paste the link below within 30 minutes. Each link works once.")
                    step(3, "This iPhone stays signed in as long as you use it at least once a month.")
                }

                VStack(alignment: .leading, spacing: Tokens.Space.s) {
                    TextField("https://…#pair=…", text: $input, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(TypeScale.mono)
                        .padding(Tokens.Space.m)
                        .background(Tokens.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.m, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.m, style: .continuous).stroke(Tokens.hairline, lineWidth: 0.5))
                        .accessibilityIdentifier("pair-link")

                    HStack(spacing: Tokens.Space.s) {
                        PasteButton(payloadType: String.self) { strings in
                            if let text = strings.first { input = text }
                        }
                        .buttonBorderShape(.capsule)
                        .labelStyle(.titleAndIcon)

                        Button {
                            Task { await model.pair(input) }
                        } label: {
                            HStack {
                                Spacer()
                                if model.pairingBusy { ProgressView().controlSize(.small) }
                                Text("Connect").font(TypeScale.subhead)
                                Spacer()
                            }
                            .frame(height: 44)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Tokens.accent)
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.pairingBusy)
                    }
                }

                if let error = model.pairingError {
                    Label(error, systemImage: "exclamationmark.triangle")
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
                .frame(width: 22, height: 22)
                .background(Tokens.accentSoft, in: Circle())
            Text(text)
                .font(TypeScale.footnote)
                .foregroundStyle(Tokens.textSecondary)
        }
    }
}
