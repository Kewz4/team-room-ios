import SwiftUI

struct DeliveryCenter: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let agentId: String
    @State private var records: [ChatMessage] = []
    @State private var editing: ChatMessage?
    @State private var error: String?
    @State private var deletedId: String?
    @State private var loading = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(records.filter { $0.state != "dismissed" }) { item in
                        deliveryRow(item)
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button { Task { await beginEdit(item) } } label: { Label("Edit", systemImage: "pencil") }
                                    .tint(Tokens.accent)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { Task { await remove(item) } } label: { Label("Delete", systemImage: "trash") }
                            }
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") { Task { await beginEdit(item) } }
                                Button("Delete", systemImage: "trash", role: .destructive) { Task { await remove(item) } }
                            }
                    }
                    if !loading && records.allSatisfy({ $0.state == "dismissed" }) {
                        Text("No failed deliveries").foregroundStyle(.secondary)
                    }
                } header: { Text("Delivery issues") } footer: {
                    Text("Swipe right to edit or left to delete. Saving an edit does not send it; use Retry when ready. Check the conversation before retrying an interrupted turn.")
                }
                let deleted = records.filter { $0.state == "dismissed" }
                if !deleted.isEmpty {
                    Section {
                        DisclosureGroup("Deleted deliveries (\(deleted.count))") {
                            ForEach(deleted) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.text ?? "").font(.subheadline).lineLimit(2)
                                    Button("Restore") { Task { await restore(item.id) } }
                                }
                            }
                        }
                    }
                }
            }
            .overlay { if loading { ProgressView() } }
            .safeAreaInset(edge: .bottom) {
                if let deletedId {
                    HStack {
                        Text("Delivery deleted")
                        Spacer()
                        Button("Undo") { Task { await restore(deletedId) } }.accessibilityLabel("Undo delete")
                    }
                    .font(.subheadline)
                    .padding()
                    .background(Tokens.surface)
                }
            }
            .navigationTitle("Delivery queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task { await load() }
        .sheet(item: $editing) { item in
            DeliveryEditor(message: item) { text in
                if model.isUITesting {
                    if let index = records.firstIndex(where: { $0.id == item.id }) { records[index].text = text; records[index].editedAt = "test" }
                } else {
                    try await model.client.editDelivery(id: item.id, agentId: agentId, text: text)
                    await load()
                    model.refresh()
                }
            }
        }
        .alert("Delivery queue", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    private func deliveryRow(_ item: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(item.editedAt != nil ? "Edited · ready to retry" : item.state == "interrupted" ? "Interrupted delivery" : "Failed delivery", systemImage: "exclamationmark.circle")
                    .font(.caption.weight(.semibold)).foregroundStyle(Tokens.failure)
                Spacer()
                Text(TimeFormat.relative(item.createdAt)).font(.caption2).foregroundStyle(.secondary)
            }
            Text(item.text ?? "").font(.subheadline).lineLimit(3)
            if let error = item.error { Text(error).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            if ["failed", "interrupted"].contains(item.state ?? "") {
                Button("Retry") {
                    Task {
                        do {
                            if model.isUITesting { records.removeAll { $0.id == item.id } }
                            else { try await model.client.retry(id: item.id); await load(); model.refresh() }
                        } catch { self.error = error.localizedDescription }
                    }
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("delivery-" + item.id)
    }

    private func load() async {
        defer { loading = false }
        #if DEBUG
        if model.isUITesting { if records.isEmpty { records = TestFixtures.deliveries }; return }
        #endif
        do { let history = try await model.client.deliveryHistory(agentId: agentId); records = Array(history.reversed()) }
        catch { self.error = error.localizedDescription }
    }

    private func beginEdit(_ item: ChatMessage) async {
        do {
            if model.isUITesting { editing = item }
            else { editing = try await model.client.delivery(id: item.id, agentId: agentId) }
        }
        catch { self.error = error.localizedDescription }
    }

    private func remove(_ item: ChatMessage) async {
        do {
            if !model.isUITesting { try await model.client.deleteDelivery(id: item.id, agentId: agentId) }
            if let index = records.firstIndex(where: { $0.id == item.id }) { records[index].state = "dismissed" }
            deletedId = item.id
            model.refresh()
        } catch { self.error = error.localizedDescription }
    }

    private func restore(_ id: String) async {
        do {
            if !model.isUITesting { try await model.client.restoreDelivery(id: id, agentId: agentId) }
            if let index = records.firstIndex(where: { $0.id == id }) { records[index].state = "failed" }
            deletedId = nil
            model.refresh()
        } catch { self.error = error.localizedDescription }
    }
}

struct DeliveryEditor: View {
    let message: ChatMessage
    let save: (String) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var saving = false
    @State private var error: String?

    init(message: ChatMessage, save: @escaping (String) async throws -> Void) {
        self.message = message
        self.save = save
        _text = State(initialValue: message.text ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text("Save your changes, then use Retry to send the message.").font(.footnote).foregroundStyle(.secondary)
                if message.redacted == true { Text("Sensitive values are hidden in this editable copy. Review it before retrying.").font(.footnote).foregroundStyle(Tokens.working) }
                TextEditor(text: $text).accessibilityIdentifier("delivery-editor")
                if let error { Text(error).foregroundStyle(Tokens.failure).font(.footnote) }
            }
            .padding()
            .navigationTitle("Edit failed delivery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save changes") {
                        saving = true
                        Task {
                            defer { saving = false }
                            do { try await save(text); dismiss() } catch { self.error = error.localizedDescription }
                        }
                    }
                    .disabled(saving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 40000)
                }
            }
        }
    }
}
