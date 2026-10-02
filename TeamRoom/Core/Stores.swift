import Foundation
import Observation

// Separate observable stores so that a streamed answer in the team chat does not redraw the board, and a
// teammate's activity frame does not redraw an open conversation. Every store only assigns when a value
// actually changed, which keeps SwiftUI from re-rendering identical rows.

@MainActor
@Observable
final class TeamStore {
    var agents: [Agent] = []
    var coordinators: [Coordinator] = []
    var relay: RelaySummary?
    var revision = 0
    var revs: [String: Int] = [:]
    var publicOrigins: [String] = []
    var serverTime: String?
    var lastSync: Date?

    func agent(_ id: String) -> Agent? { agents.first { $0.id == id } }

    func apply(_ snapshot: TeamSnapshot) {
        replace(snapshot.agents)
        if coordinators != snapshot.coordinators { coordinators = snapshot.coordinators }
        if relay != snapshot.relay { relay = snapshot.relay }
        if let origins = snapshot.publicOrigins, origins != publicOrigins { publicOrigins = origins }
        if let value = snapshot.revision { revision = max(revision, value) }
        serverTime = snapshot.serverTime
        lastSync = Date()
    }

    func replace(_ list: [Agent]) {
        guard !list.isEmpty else { return }
        // Keep fields only the conversation knows (stream text) out of the summary comparison.
        if list != agents { agents = list }
        for agent in list { if let rev = agent.rev { revs[agent.id] = rev } }
        lastSync = Date()
    }

    func applyActivity(_ frame: LiveFrame) {
        guard let id = frame.agentId, let index = agents.firstIndex(where: { $0.id == id }) else { return }
        var agent = agents[index]
        if let execution = frame.execution { agent.execution = execution }
        if let state = frame.state { agent.state = state }
        if let connection = frame.connection { agent.connection = connection }
        if let canStop = frame.canStop { agent.canStop = canStop }
        if agent != agents[index] { agents[index] = agent }
    }

    var workingCount: Int { agents.filter { $0.state == "working" }.count }
    var needsInput: [Agent] { agents.filter { !($0.prompts ?? []).isEmpty } }
    var failedDeliveries: Int { agents.reduce(0) { $0 + ($1.queue ?? []).filter { ["failed", "interrupted"].contains($0.state ?? "") }.count } }
}

@MainActor
@Observable
final class ConversationStore {
    let agentId: String
    var items: [ConversationItem] = []
    var messages: [ChatMessage] = []
    var liveText = ""
    var queue: [ChatMessage] = []
    var prompts: [AgentPrompt] = []
    var loaded = false
    var loading = false
    var error: String?
    var rev = -1
    var etag: String?

    init(agentId: String) {
        self.agentId = agentId
    }

    func apply(_ payload: ConversationPayload, etag: String?) {
        self.etag = etag
        rev = payload.rev ?? rev
        if messages != payload.messages || items.isEmpty {
            messages = payload.messages
            MarkdownRenderer.shared.warm(payload.messages.suffix(40).compactMap { $0.text })
        }
        let built = ConversationBuilder.items(messages: payload.messages, events: payload.events)
        if built != items { items = built }
        let live = payload.liveText ?? ""
        if live != liveText { liveText = live }
        if queue != payload.queue { queue = payload.queue }
        if prompts != payload.prompts { prompts = payload.prompts }
        error = payload.error
        loaded = true
    }

    /// Applies a streamed delta; false when the frames are out of step and a resync is needed.
    func applyStream(_ frame: LiveFrame) -> Bool {
        guard let next = StreamDelta.apply(frame, to: liveText) else { return false }
        if next != liveText { liveText = next }
        return true
    }

    /// The streamed reply, unless the saved transcript already shows the same text.
    var visibleLiveText: String? {
        let text = liveText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let saved = messages.suffix(6).contains { $0.role == "assistant" && ($0.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == text }
        return saved ? nil : liveText
    }

    var pendingQueue: [ChatMessage] { queue.filter { ["queued", "waiting_busy", "waiting_connection", "sending"].contains($0.state ?? "") } }
    var failures: [ChatMessage] { queue.filter { ["failed", "interrupted"].contains($0.state ?? "") } }
}

@MainActor
@Observable
final class RoomStore {
    var messages: [RoomMessage] = []
    var coordinators: [Coordinator] = []
    var loaded = false
    var sending = false
    var error: String?

    func apply(_ page: RoomPage) {
        let sorted = page.messages
        if sorted != messages { messages = sorted }
        if !page.coordinators.isEmpty, page.coordinators != coordinators { coordinators = page.coordinators }
        loaded = true
    }

    func upsert(_ message: RoomMessage) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            if messages[index] != message { messages[index] = message }
        } else {
            messages.append(message)
        }
    }

    var answering: RoomMessage? { messages.last { $0.role == "coordinator" && $0.isInProgress } }
}

@MainActor
@Observable
final class BoardStore {
    var report: ProgressReport?
    var loading = false
    var error: String?
    var loadedAt: Date?
}

/// Tabs and navigation, including deep links from Bark notifications (teamroom://...).
@MainActor
@Observable
final class Router {
    enum Tab: Hashable {
        case team, agents, board, notes, inbox
    }

    var tab: Tab = .team
    var agentPath: [String] = []
    var focusRoomMessage: String?
    var pendingPairLink: String?
    var showSettings = false
    var openNoteId: String?

    /// teamroom://chat[/id], teamroom://agent/<id>, teamroom://board, teamroom://notes[/id], teamroom://inbox, teamroom://settings,
    /// teamroom://pair?link=<device link>
    @discardableResult
    func open(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "teamroom" else { return false }
        let host = (url.host ?? "").lowercased()
        let parts = url.pathComponents.filter { $0 != "/" }
        switch host {
        case "chat", "team":
            tab = .team
            focusRoomMessage = parts.first
        case "agent":
            guard let id = parts.first, !id.isEmpty else { tab = .agents; return true }
            tab = .agents
            agentPath = [id]
        case "board", "progress":
            tab = .board
        case "inbox":
            tab = .inbox
        case "notes":
            tab = .notes
            openNoteId = parts.first
        case "settings":
            showSettings = true
        case "pair":
            let link = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "link" }?.value
            pendingPairLink = link
        default:
            return false
        }
        return true
    }

    func openAgent(_ id: String) {
        tab = .agents
        agentPath = [id]
    }
}

/// Last known state on disk, so the app opens instantly with content and shows "Updating" instead of a spinner.
enum DiskCache {
    private static let queue = DispatchQueue(label: "teamroom.cache", qos: .utility)

    private static var directory: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let url = base.appendingPathComponent("TeamRoom", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func file(_ name: String) -> URL? {
        let safe = name.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
        return directory?.appendingPathComponent(safe + ".json")
    }

    static func save<T: Encodable>(_ value: T, as name: String) {
        guard let url = file(name), let data = try? JSONEncoder().encode(value) else { return }
        queue.async { try? data.write(to: url, options: .atomic) }
    }

    static func load<T: Decodable>(_ type: T.Type, name: String) -> T? {
        guard let url = file(name), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func clear() {
        guard let directory else { return }
        queue.async { try? FileManager.default.removeItem(at: directory) }
    }
}

/// Kewz's notes, local-first: every edit is saved on the phone immediately and uploaded in the background,
/// so writing works offline and nothing is lost when the PC is unreachable. The newest edit wins.
@MainActor
@Observable
final class NotesStore {
    var notes: [Note] = []
    var loaded = false
    var syncing = false
    var error: String?

    var visible: [Note] {
        notes.filter { $0.deleted != true }.sorted {
            let left = ($0.pinned == true ? 1 : 0, $0.updatedAt)
            let right = ($1.pinned == true ? 1 : 0, $1.updatedAt)
            return left > right
        }
    }

    var pending: [Note] { notes.filter { $0.pendingSync == true } }

    func note(_ id: String) -> Note? { notes.first { $0.id == id } }

    func restore() {
        if let page = DiskCache.load(NotesPage.self, name: "notes") {
            notes = page.notes
        }
    }

    func persist() {
        DiskCache.save(NotesPage(notes: notes), as: "notes")
    }

    func upsertLocal(_ note: Note) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            if notes[index] != note { notes[index] = note }
        } else {
            notes.append(note)
        }
        persist()
    }

    /// Server copies replace local ones unless the local copy is a newer edit still waiting to upload.
    func merge(server: [Note]) {
        var byId = Dictionary(notes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for remote in server {
            if let local = byId[remote.id], local.pendingSync == true, local.updatedAt > remote.updatedAt { continue }
            byId[remote.id] = remote
        }
        let merged = Array(byId.values)
        if Set(merged) != Set(notes) { notes = merged }
        loaded = true
        persist()
    }

    static func timestamp(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
