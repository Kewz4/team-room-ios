import SwiftUI

struct PairView: View {
    @Environment(AppModel.self) private var model
    @State private var input = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Team Room")
                        .font(.largeTitle.bold())
                    Text("Your private console for the local AI teammates, now native on iPhone.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("On the PC, open Team Room → Connection settings → Create device link.", systemImage: "1.circle")
                    Label("Copy the link and paste it here within 30 minutes. Each link works once.", systemImage: "2.circle")
                    Label("The session is kept in your iPhone Keychain; nothing is stored in the repo.", systemImage: "3.circle")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    TextField("https://….trycloudflare.com/#pair=…", text: $input, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.footnote.monospaced())
                        .padding(12)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))

                    Button {
                        Task { await model.pair(input) }
                    } label: {
                        HStack {
                            Spacer()
                            if model.pairingBusy { ProgressView().controlSize(.small) }
                            Text("Connect")
                            Spacer()
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.pairingBusy)
                }

                if let error = model.pairingError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding(22)
        }
    }
}
