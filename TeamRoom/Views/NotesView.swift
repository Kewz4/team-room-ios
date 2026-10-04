import SwiftUI

/// Kewz's personal notes. Saved on the phone instantly and synced to the PC (private; never shared with the team
/// unless a note is switched to "Share with coordinators", which lets the team chat read it).
struct NotesView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                let notes = filtered
                if notes.isEmpty {
                    EmptyStateView(title: search.isEmpty ? "No notes yet" : "No matches",
                                   message: search.isEmpty ? "Tap the pencil to write one. Notes sync to your PC and stay private unless you share one with the coordinators." : "Try another word.",
                                   systemImage: "note.text")
                        .listRowBackground(Color.clear)
                }
                ForEach(notes) { note in
                    NavigationLink(value: note.id) {
                        NoteRow(note: note)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { model.deleteNote(note.id) } label: { Label("Delete", systemImage: "trash") }
                    }
                    .swipeActions(edge: .leading) {
                        Button { model.updateNote(note.id, pinned: !(note.pinned ?? false)) } label: {
                            Label(note.pinned == true ? "Unpin" : "Pin", systemImage: note.pinned == true ? "pin.slash" : "pin")
                        }
                        .tint(Tokens.working)
                    }
                    .contextMenu {
                        Button { model.updateNote(note.id, pinned: !(note.pinned ?? false)) } label: {
                            Label(note.pinned == true ? "Unpin" : "Pin", systemImage: "pin")
                        }
                        Button { model.updateNote(note.id, shared: !(note.shared ?? false)) } label: {
                            Label(note.shared == true ? "Stop sharing with coordinators" : "Share with coordinators", systemImage: "person.2")
                        }
                        ShareLink(item: note.text) { Label("Share…", systemImage: "square.and.arrow.up") }
                        Button(role: .destructive) { model.deleteNote(note.id) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Tokens.background)
            .navigationTitle("Notes")
            .searchable(text: $search, prompt: "Search notes")
            .toolbar {
                SettingsToolbarItem(router: model.router)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let note = model.newNote()
                        path = [note.id]
                    } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("New note")
                    .accessibilityIdentifier("new-note")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let error = model.notes.error, !model.notes.pending.isEmpty {
                    Label("Saved on this iPhone; will sync when the PC is reachable. \(error)", systemImage: "icloud.slash")
                        .font(TypeScale.caption)
                        .foregroundStyle(Tokens.textSecondary)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                }
            }
            .refreshable { await model.syncNotes() }
            .navigationDestination(for: String.self) { id in
                NoteEditor(noteId: id)
            }
            .onChange(of: model.router.openNoteId) { _, id in
                guard let id else { return }
                path = [id]
                model.router.openNoteId = nil
            }
        }
    }

    private var filtered: [Note] {
        let notes = model.notes.visible
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return notes }
        return notes.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }
}

struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if note.pinned == true { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(Tokens.working) }
                Text(note.displayTitle)
                    .font(.headline)
                    .foregroundStyle(Tokens.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if note.shared == true {
                    Image(systemName: "person.2.fill").font(.caption2).foregroundStyle(Tokens.info)
                        .accessibilityLabel("Shared with coordinators")
                }
                if note.pendingSync == true {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.caption2).foregroundStyle(Tokens.textTertiary)
                        .accessibilityLabel("Not synced yet")
                }
            }
            HStack(spacing: 6) {
                RelativeTimeText(iso: note.updatedAt)
                    .font(TypeScale.caption)
                    .foregroundStyle(Tokens.textTertiary)
                Text(note.preview.isEmpty ? "No additional text" : note.preview)
                    .font(TypeScale.caption)
                    .foregroundStyle(Tokens.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}

/// Plain-text editor: the first line is the title. Saves as you type.
struct NoteEditor: View {
    let noteId: String
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @State private var loaded = false
    @FocusState private var focused: Bool

    var body: some View {
        let note = model.notes.note(noteId)
        TextEditor(text: $text)
            .font(TypeScale.body)
            .focused($focused)
            .scrollContentBackground(.hidden)
            // 1.2 (Kewz, 2026-10-04: "there's a point where I can't scroll down"): room below the last line, so it
            // always scrolls clear of the screen edge, and a downward drag puts the keyboard away.
            .contentMargins(.bottom, Tokens.Space.xl * 3, for: .scrollContent)
            .scrollDismissesKeyboard(.interactively)
            .padding(.horizontal, 12)
            .background(Tokens.background)
            .accessibilityIdentifier("note-editor")
            .navigationTitle(note?.displayTitle ?? "Note")
            .navigationBarTitleDisplayMode(.inline)
            // The floating tab bar no longer covers the end of a long note.
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { model.updateNote(noteId, pinned: !(note?.pinned ?? false)) } label: {
                            Label(note?.pinned == true ? "Unpin" : "Pin to top", systemImage: "pin")
                        }
                        Toggle(isOn: Binding(get: { note?.shared == true }, set: { model.updateNote(noteId, shared: $0) })) {
                            Label("Share with coordinators", systemImage: "person.2")
                        }
                        ShareLink(item: text) { Label("Share…", systemImage: "square.and.arrow.up") }
                        Button(role: .destructive) { model.deleteNote(noteId) } label: { Label("Delete", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
                // 1.2: iOS 26's keyboard toolbar pushed this editor's text under the keyboard (Apple developer forums
                // thread 799692), so the hide-keyboard button lives in the navigation bar instead.
                if focused {
                    ToolbarItem(placement: .topBarTrailing) { HideKeyboardButton { focused = false } }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if note?.shared == true {
                    Label("Shared with the coordinators: the team chat can read this note.", systemImage: "person.2.fill")
                        .font(TypeScale.caption)
                        .foregroundStyle(Tokens.info)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Tokens.Space.m)
                        .padding(.vertical, 6)
                        .background(Tokens.info.opacity(0.08))
                }
            }
            .onAppear {
                guard !loaded else { return }
                text = note?.text ?? ""
                loaded = true
                if text.isEmpty { focused = true }
            }
            .onChange(of: text) { _, value in
                guard loaded, value != model.notes.note(noteId)?.text else { return }
                model.updateNote(noteId, text: value)
            }
            .onDisappear { model.discardIfEmpty(noteId) }
    }
}
