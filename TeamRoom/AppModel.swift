import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable { case pairing, connecting, ready }

    var phase: Phase = .pairing
    var pairingError: String?
    var pairingBusy = false
    var baseURLString = ""
    var socketStatus: LiveConnection.Status = .offline
    var syncError: String?
    var actionError: String?
    var drafts: [String: String] = [:]
    var roomDraft = ""
    var sendingTo: Set<String> = []
    var promptBusy: Set<String> = []
    var artifact: ArtifactRequest?
    var bark: BarkStatus?
    var updating = false
    var lastSeenRoomId = UserDefaults.standard.string(forKey: "teamroom.room.lastSeen")

    let team = TeamStore()
    let room = RoomStore()
    let board = BoardStore()
    let notes = NotesStore()
    let router = Router()
    let notifications = TeamNotifications()
    let client = TeamRoomClient()
    let images: ImageStore

    @ObservationIgnored private var conversations: [String: ConversationStore] = [:]
    @ObservationIgnored private var visibleAgents: Set<String> = []
    @ObservationIgnored private var live: LiveConnection!
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var teamTask: Task<Void, Never>?
    @ObservationIgnored private var conversationTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var backgroundTask: Task<Void, Never>?
    @ObservationIgnored private var foreground = true
    @ObservationIgnored private var eventCache: [String: EventDetail] = [:]
    @ObservationIgnored private var migrating = false
    @ObservationIgnored private var noteUploads: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var notesSyncing = false

    init() {
        images = ImageStore(client: client)
        live = LiveConnection(client: client)
        live.onFrame = { [weak self] frame in self?.handle(frame) }
        live.onStatus = { [weak self] status in self?.socketChanged(status) }
        notifications.client = client
        notifications.openAgent = { [weak self] id in self?.router.openAgent(id) }
    }

    var isUITesting: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-ui-testing")
        #else
        return false
        #endif
    }

    var isLive: Bool { socketStatus == .live }

    // MARK: - Lifecycle

    func boot() async {
        #if DEBUG
        if isUITesting { TestFixtures.load(self); return }
        #endif
        let savedURL = UserDefaults.standard.string(forKey: "teamroom.baseURL")
        let token = KeychainStore.loadToken()
        guard let savedURL, let url = URL(string: savedURL), let token else {
            phase = .pairing
            return
        }
        baseURLString = savedURL
        notifications.configure(server: savedURL)
        await client.configure(baseURL: url, cookie: token)
        // Instant launch: show the last known team, chat and board while the live data loads.
        if restoreCache() { phase = .ready } else { phase = .connecting }
        await connect()
    }

    private func restoreCache() -> Bool {
        var restored = false
        if let snapshot = DiskCache.load(TeamSnapshot.self, name: "team"), !snapshot.agents.isEmpty {
            team.apply(snapshot)
            team.lastSync = nil
            restored = true
        }
        if let page = DiskCache.load(RoomPage.self, name: "room") { room.apply(page) }
        if let report = DiskCache.load(ProgressReport.self, name: "board") { board.report = report }
        notes.restore()
        return restored
    }

    private func connect() async {
        updating = true
        defer { updating = false }
        do {
            try await refreshTeam()
            phase = .ready
        } catch let error as ClientError where error.status == 401 {
            signOut(message: "This device's session expired. Create a new device link on the PC and paste it here.")
            return
        } catch {
            syncError = (error as? ClientError)?.message ?? error.localizedDescription
            phase = .ready
        }
        live.start()
        startPolling()
        Task { await refreshRoom() }
        Task { await refreshBoard() }
        Task { await refreshBark() }
        Task { await syncNotes() }
        Task { await notifications.refreshPermission() }
    }

    func sceneChanged(_ active: Bool) {
        guard !isUITesting, phase == .ready else { return }
        foreground = active
        if active {
            backgroundTask?.cancel()
            live.start()
            live.setForeground(true)
            startPolling()
            Task {
                try? await refreshTeam()
                for id in visibleAgents { await refreshConversation(id) }
                await refreshRoom()
            }
        } else {
            // Tell the PC first so it starts sending background notifications, then close the socket
            // before iOS suspends the app.
            live.setForeground(false)
            pollTask?.cancel()
            backgroundTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled, !self.foreground else { return }
                self.live.stop()
            }
        }
    }

    private func socketChanged(_ status: LiveConnection.Status) {
        socketStatus = status
        if status == .live { syncError = nil }
    }

    // MARK: - Pairing

    func pair(_ input: String) async {
        pairingBusy = true
        pairingError = nil
        defer { pairingBusy = false }
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("teamroom://"), let url = URL(string: text),
           let link = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "link" })?.value {
            text = link
        }
        guard let parsed = Self.parse(input: text, fallbackOrigin: baseURLString) else {
            pairingError = "Paste the full device link from the PC (it contains #pair=…)."
            return
        }
        do {
            await client.configure(baseURL: parsed.base, cookie: nil)
            guard let token = parsed.token else {
                pairingError = "That is a server address without a device link. On the PC: Team Room → Connection settings → Create device link, then paste the whole link."
                return
            }
            guard let cookie = try await client.signIn(pairingToken: token) else {
                pairingError = "Sign-in did not return a session. Generate a new device link on the PC and try again."
                return
            }
            KeychainStore.save(token: cookie)
            UserDefaults.standard.set(parsed.base.absoluteString, forKey: "teamroom.baseURL")
            baseURLString = parsed.base.absoluteString
            notifications.configure(server: baseURLString)
            phase = .connecting
            await connect()
        } catch {
            pairingError = (error as? ClientError)?.message ?? error.localizedDescription
        }
    }

    static func parse(input: String, fallbackOrigin: String) -> (base: URL, token: String?)? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        var token: String?
        if let range = text.range(of: "pair=") {
            let remainder = text[range.upperBound...]
            let value = remainder.prefix { $0 != "&" && $0 != "#" && !$0.isWhitespace }
            if !value.isEmpty { token = String(value) }
        }
        if let origin = originURL(from: text) { return (origin, token) }
        if !text.contains("://"), let fallback = URL(string: fallbackOrigin), fallback.host != nil {
            return (fallback, token ?? text)
        }
        return nil
    }

    static func originURL(from text: String) -> URL? {
        guard var components = URLComponents(string: text),
              let scheme = components.scheme,
              scheme.hasPrefix("http"),
              components.host != nil else { return nil }
        components.path = ""
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.url
    }

    // MARK: - Refresh

    func refresh() {
        Task {
            updating = true
            defer { updating = false }
            try? await refreshTeam()
            for id in visibleAgents { await refreshConversation(id, force: true) }
            await refreshRoom()
        }
    }

    func refreshTeam() async throws {
        guard !isUITesting else { return }
        do {
            let snapshot = try await client.team()
            team.apply(snapshot)
            syncError = nil
            notifications.observe(team.agents)
            DiskCache.save(snapshot, as: "team")
            await migrateToStableOrigin()
        } catch let error as ClientError {
            if error.status == 401 {
                signOut(message: "This device's session expired. Create a new device link on the PC.")
            } else {
                syncError = error.message
            }
            throw error
        }
    }

    /// Moves this device to the PC's permanent address (Tailscale Funnel) once the session is proven there.
    private func migrateToStableOrigin() async {
        guard !migrating, let stable = team.publicOrigins.first, let url = URL(string: stable),
              url.scheme == "https", stable != baseURLString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) else { return }
        if let current = URL(string: baseURLString), current.host == url.host, current.port == url.port { return }
        migrating = true
        defer { migrating = false }
        guard let status = try? await client.sessionStatus(at: url), status.authenticated else { return }
        let token = KeychainStore.loadToken()
        await client.configure(baseURL: url, cookie: token)
        baseURLString = url.absoluteString
        UserDefaults.standard.set(url.absoluteString, forKey: "teamroom.baseURL")
        live.stop()
        live.start()
    }

    func conversation(_ agentId: String) -> ConversationStore {
        if let store = conversations[agentId] { return store }
        let store = ConversationStore(agentId: agentId)
        if let cached = DiskCache.load(ConversationPayload.self, name: "conversation-" + agentId) {
            store.apply(cached, etag: nil)
        }
        conversations[agentId] = store
        if conversations.count > 6, let evict = conversations.keys.first(where: { !visibleAgents.contains($0) && $0 != agentId }) {
            conversations[evict] = nil
        }
        return store
    }

    func conversationAppeared(_ agentId: String) {
        visibleAgents.insert(agentId)
        live.subscribe(agentId)
        notifications.markRead(agentId: agentId)
        Task { await refreshConversation(agentId, force: true) }
    }

    func conversationDisappeared(_ agentId: String) {
        visibleAgents.remove(agentId)
        live.unsubscribe(agentId)
    }

    func refreshConversation(_ agentId: String, force: Bool = false) async {
        guard !isUITesting else { return }
        let store = conversation(agentId)
        if store.loading && !force { return }
        store.loading = true
        defer { store.loading = false }
        do {
            let result = try await client.conversation(agentId: agentId, etag: store.etag)
            if let payload = result.payload {
                store.apply(payload, etag: result.etag)
                DiskCache.save(payload, as: "conversation-" + agentId)
            }
            store.error = nil
        } catch {
            store.error = (error as? ClientError)?.message ?? error.localizedDescription
        }
    }

    private func scheduleConversationRefresh(_ agentId: String) {
        conversationTasks[agentId]?.cancel()
        conversationTasks[agentId] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self?.refreshConversation(agentId)
        }
    }

    func refreshRoom() async {
        guard !isUITesting else { return }
        do {
            let page = try await client.room()
            room.apply(page)
            DiskCache.save(page, as: "room")
        } catch {
            room.error = (error as? ClientError)?.message ?? error.localizedDescription
        }
    }

    func refreshBoard(fresh: Bool = false) async {
        guard !isUITesting else { return }
        board.loading = true
        defer { board.loading = false }
        do {
            let report = try await client.progress(fresh: fresh)
            board.report = report
            board.loadedAt = Date()
            board.error = nil
            DiskCache.save(report, as: "board")
        } catch {
            board.error = (error as? ClientError)?.message ?? error.localizedDescription
        }
    }

    // MARK: - Polling (safety net; the socket drives normal updates)

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval: Duration = self?.isLive == true ? .seconds(60) : .seconds(8)
                try? await Task.sleep(for: interval)
                guard let self, !Task.isCancelled, self.foreground else { return }
                try? await self.refreshTeam()
                if !self.isLive {
                    for id in self.visibleAgents { await self.refreshConversation(id) }
                    await self.refreshRoom()
                    self.live.reconnectNow()
                }
            }
        }
    }

    // MARK: - Live frames

    private func handle(_ frame: LiveFrame) {
        switch frame.type {
        case "connected":
            if let agents = frame.agents { team.replace(agents); notifications.observe(team.agents) }
            if let revs = frame.revs { checkRevisions(revs, force: true) }
            Task { await refreshRoom() }
        case "changed":
            if let revision = frame.revision { team.revision = max(team.revision, revision) }
            if let revs = frame.revs { checkRevisions(revs, force: false) }
        case "team":
            if let agents = frame.agents {
                team.replace(agents)
                notifications.observe(team.agents)
                scheduleTeamSnapshotSave()
            }
        case "activity":
            team.applyActivity(frame)
        case "stream":
            guard let id = frame.agentId, let store = conversations[id] else { return }
            if !store.applyStream(frame) {
                live.resync(id)
                scheduleConversationRefresh(id)
            }
        case "room":
            if let message = frame.message { room.upsert(message) }
        case "notes":
            Task { await syncNotes() }
        default:
            break
        }
    }

    private func checkRevisions(_ revs: [String: Int], force: Bool) {
        for id in visibleAgents {
            guard let store = conversations[id], let rev = revs[id] else { continue }
            if force || rev != store.rev { scheduleConversationRefresh(id) }
        }
    }

    private func scheduleTeamSnapshotSave() {
        teamTask?.cancel()
        teamTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled else { return }
            DiskCache.save(TeamSnapshot(revision: self.team.revision, publicOrigins: self.team.publicOrigins, relay: self.team.relay,
                                        coordinators: self.team.coordinators, agents: self.team.agents), as: "team")
        }
    }

    // MARK: - Team chat

    var unreadRoomCount: Int {
        guard let last = room.messages.last(where: { $0.role == "coordinator" && $0.state == "answered" }) else { return 0 }
        guard let seen = lastSeenRoomId else { return 0 }
        if last.id == seen { return 0 }
        guard let index = room.messages.firstIndex(where: { $0.id == seen }) else { return 1 }
        return room.messages[(index + 1)...].filter { $0.role == "coordinator" && $0.state == "answered" }.count
    }

    func markRoomSeen() {
        guard let last = room.messages.last(where: { $0.role == "coordinator" && $0.state == "answered" }) else { return }
        if lastSeenRoomId != last.id {
            lastSeenRoomId = last.id
            UserDefaults.standard.set(last.id, forKey: "teamroom.room.lastSeen")
        }
    }

    func ask(_ text: String, mention: String? = nil) async {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let mention, !trimmed.lowercased().hasPrefix("@") { trimmed = "@\(mention) \(trimmed)" }
        room.sending = true
        defer { room.sending = false }
        let id = "q-" + UUID().uuidString.lowercased()
        let optimistic = RoomMessage(id: id, role: "user", text: trimmed, createdAt: ISO8601DateFormatter().string(from: Date()), state: "sending")
        room.upsert(optimistic)
        roomDraft = ""
        do {
            let response = try await client.ask(id: id, text: trimmed)
            if let question = response.question { room.upsert(question) }
            if let answer = response.answer { room.upsert(answer) }
        } catch {
            room.messages.removeAll { $0.id == id }
            roomDraft = trimmed
            actionError = (error as? ClientError)?.message ?? error.localizedDescription
        }
    }

    func stopAnswer(_ id: String) async {
        do { try await client.stopAnswer(id: id) } catch { actionError = (error as? ClientError)?.message ?? error.localizedDescription }
    }

    func retryAnswer(_ id: String) async {
        do { try await client.retryAnswer(id: id) } catch { actionError = (error as? ClientError)?.message ?? error.localizedDescription }
    }

    // MARK: - Agent actions

    func send(_ text: String, to agentId: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sendingTo.insert(agentId)
        defer { sendingTo.remove(agentId) }
        do {
            try await client.send(agentId: agentId, text: trimmed, id: UUID().uuidString.lowercased(), mode: nil)
            drafts[agentId] = ""
            scheduleConversationRefresh(agentId)
        } catch {
            actionError = (error as? ClientError)?.message ?? error.localizedDescription
        }
    }

    func cancelQueued(id: String, agentId: String) async {
        do {
            try await client.cancel(id: id)
            scheduleConversationRefresh(agentId)
        } catch {
            actionError = (error as? ClientError)?.message ?? error.localizedDescription
        }
    }

    func retryMessage(id: String, agentId: String) async {
        do {
            try await client.retry(id: id)
            scheduleConversationRefresh(agentId)
        } catch {
            actionError = (error as? ClientError)?.message ?? error.localizedDescription
        }
    }

    func stopTurn(_ agentId: String) async {
        do {
            try await client.stop(agentId: agentId)
            scheduleConversationRefresh(agentId)
        } catch {
            actionError = (error as? ClientError)?.message ?? error.localizedDescription
        }
    }

    func checkRunners() async {
        do {
            try await client.refreshConnections()
            try? await refreshTeam()
        } catch {
            actionError = (error as? ClientError)?.message ?? error.localizedDescription
        }
    }

    func respond(agentId: String, to prompt: AgentPrompt, answer: PromptAnswer) async {
        guard !promptBusy.contains(prompt.id) else { return }
        promptBusy.insert(prompt.id)
        defer { promptBusy.remove(prompt.id) }
        do {
            try await client.respond(agentId: agentId, promptId: prompt.id, answer: answer)
            scheduleConversationRefresh(agentId)
            try? await refreshTeam()
        } catch {
            actionError = (error as? ClientError)?.message ?? error.localizedDescription
        }
    }

    func createDeviceLink() async -> DeviceLink? {
        do {
            return try await client.deviceLink()
        } catch {
            actionError = (error as? ClientError)?.message ?? error.localizedDescription
            return nil
        }
    }

    func detail(for event: LiveEvent, agentId: String) async -> EventDetail? {
        if let cached = eventCache[event.id] { return cached }
        do {
            let detail = try await client.eventDetail(agentId: event.agentId ?? agentId, id: event.id)
            eventCache[event.id] = detail
            if eventCache.count > 200 { eventCache.removeAll() }
            return detail
        } catch {
            actionError = (error as? ClientError)?.message ?? error.localizedDescription
            return nil
        }
    }

    func fullMessage(agentId: String, id: String) async -> String? {
        do {
            return try await client.fullMessage(agentId: agentId, id: id).text
        } catch {
            actionError = (error as? ClientError)?.message ?? error.localizedDescription
            return nil
        }
    }

    // MARK: - Notes

    func newNote() -> Note {
        let now = NotesStore.timestamp()
        let note = Note(id: "note-" + UUID().uuidString.lowercased(), text: "", createdAt: now, updatedAt: now, pendingSync: true)
        notes.upsertLocal(note)
        return note
    }

    /// Saves locally at once and uploads after a short pause, so typing never waits on the network.
    func updateNote(_ id: String, text: String? = nil, pinned: Bool? = nil, shared: Bool? = nil) {
        guard var note = notes.note(id) else { return }
        if let text { note.text = text }
        if let pinned { note.pinned = pinned }
        if let shared { note.shared = shared }
        note.updatedAt = NotesStore.timestamp()
        note.pendingSync = true
        notes.upsertLocal(note)
        noteUploads[id]?.cancel()
        let delay: Duration = text == nil ? .milliseconds(50) : .milliseconds(900)
        noteUploads[id] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.uploadNote(id)
        }
    }

    func deleteNote(_ id: String) {
        guard var note = notes.note(id) else { return }
        note.deleted = true
        note.updatedAt = NotesStore.timestamp()
        note.pendingSync = true
        notes.upsertLocal(note)
        noteUploads[id]?.cancel()
        noteUploads[id] = Task { [weak self] in await self?.uploadNote(id) }
    }

    /// An empty note left behind (opened, nothing typed) is removed rather than kept as "New note".
    func discardIfEmpty(_ id: String) {
        guard let note = notes.note(id), note.deleted != true,
              note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        deleteNote(id)
    }

    private func uploadNote(_ id: String) async {
        guard !isUITesting, let note = notes.note(id), note.pendingSync == true else { return }
        do {
            if note.deleted == true {
                try await client.deleteNote(id: note.id, updatedAt: note.updatedAt)
                notes.notes.removeAll { $0.id == id }
                notes.persist()
            } else {
                let response = try await client.saveNote(note)
                // The PC may hold a newer copy (edited on another device): take it.
                var stored = response.note
                stored.pendingSync = nil
                if let current = notes.note(id), current.updatedAt > note.updatedAt {
                    return // edited again while uploading; that edit uploads next
                }
                notes.upsertLocal(stored)
            }
            notes.error = nil
        } catch {
            notes.error = (error as? ClientError)?.message ?? error.localizedDescription
        }
    }

    func syncNotes() async {
        guard !isUITesting, !notesSyncing else { return }
        notesSyncing = true
        notes.syncing = true
        defer { notesSyncing = false; notes.syncing = false }
        for note in notes.pending { await uploadNote(note.id) }
        do {
            let page = try await client.notes()
            notes.merge(server: page.notes)
            notes.notes.removeAll { $0.deleted == true && $0.pendingSync != true }
            notes.persist()
            notes.error = nil
        } catch {
            notes.error = (error as? ClientError)?.message ?? error.localizedDescription
        }
    }

    // MARK: - Bark

    func refreshBark() async {
        guard !isUITesting else { return }
        bark = try? await client.barkStatus()
    }

    // MARK: - Sign out

    func signOut(message: String? = nil) {
        pollTask?.cancel()
        pollTask = nil
        live.stop()
        Task { await client.unregisterPush(); await client.signOut() }
        KeychainStore.delete()
        UserDefaults.standard.removeObject(forKey: "teamroom.baseURL")
        DiskCache.clear()
        team.agents = []
        room.messages = []
        board.report = nil
        conversations = [:]
        visibleAgents = []
        drafts = [:]
        eventCache = [:]
        syncError = nil
        pairingError = message
        phase = .pairing
    }
}
