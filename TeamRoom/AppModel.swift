import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable { case pairing, connecting, ready }

    var phase: Phase = .pairing
    var pairingError: String?
    var pairingBusy = false
    var baseURLString = ""
    var agents: [Agent] = []
    var selectedId = ""
    var revision = 0
    var lastSync: Date?
    var syncError: String?
    var socketNote = "offline"
    var drafts: [String: String] = [:]
    var actionError: String?
    var sending = false

    let client = TeamRoomClient()
    private var pollTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var socketTask: URLSessionWebSocketTask?
    private var socketGeneration = 0
    private var refreshing = false
    private var refreshAgain = false
    private var eventCache: [String: EventDetail] = [:]

    var selectedAgent: Agent? { agents.first { $0.id == selectedId } }

    // MARK: - Lifecycle

    func boot() async {
        let savedURL = UserDefaults.standard.string(forKey: "teamroom.baseURL")
        let token = KeychainStore.loadToken()
        guard let savedURL, let url = URL(string: savedURL), let token else {
            phase = .pairing
            return
        }
        baseURLString = savedURL
        await client.configure(baseURL: url, cookie: token)
        phase = .connecting
        await connect()
    }

    private func connect() async {
        do {
            let state = try await client.state(agentId: nil)
            apply(state)
            phase = .ready
            startPolling()
            startSocket()
            refresh()
        } catch let error as ClientError where error.status == 401 {
            signOut(message: "This device's session expired. Create a new device link on the PC and paste it here.")
        } catch {
            syncError = error.localizedDescription
            phase = .ready
            startPolling()
            startSocket()
        }
    }

    // MARK: - Pairing

    func pair(_ input: String) async {
        pairingBusy = true
        pairingError = nil
        defer { pairingBusy = false }
        guard let parsed = Self.parse(input: input, fallbackOrigin: baseURLString) else {
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
            phase = .connecting
            await connect()
        } catch {
            pairingError = error.localizedDescription
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

    // MARK: - Selection and refresh

    func select(_ id: String) {
        guard id != selectedId else { return }
        selectedId = id
        refresh()
    }

    func refresh() {
        guard phase == .ready else { return }
        if refreshing {
            refreshAgain = true
            return
        }
        refreshing = true
        Task { @MainActor in
            await performRefresh()
            refreshing = false
            if refreshAgain {
                refreshAgain = false
                refresh()
            }
        }
    }

    private func performRefresh() async {
        do {
            let state = try await client.state(agentId: selectedId.isEmpty ? nil : selectedId)
            apply(state)
        } catch let error as ClientError where error.status == 401 {
            signOut(message: "This device's session expired. Create a new device link on the PC.")
        } catch {
            syncError = error.localizedDescription
        }
    }

    private func apply(_ state: StateResponse) {
        agents = state.agents
        if let value = state.revision { revision = value }
        lastSync = Date()
        syncError = nil
        if selectedId.isEmpty || !agents.contains(where: { $0.id == selectedId }) {
            selectedId = defaultAgentId()
        }
    }

    private func defaultAgentId() -> String {
        if let working = agents.first(where: { $0.state == "working" }) { return working.id }
        return agents.first?.id ?? ""
    }

    private func scheduleRefresh() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            refresh()
        }
    }

    // MARK: - Polling

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled, let self else { return }
                self.refresh()
            }
        }
    }

    // MARK: - Live socket

    private func startSocket() {
        socketGeneration += 1
        let generation = socketGeneration
        Task { @MainActor in
            do {
                let request = try await client.makeWebSocketRequest()
                let task = client.session.webSocketTask(with: request)
                socketTask = task
                socketNote = "connecting"
                task.resume()
                listen(task, generation: generation)
            } catch {
                socketNote = "offline"
                scheduleReconnect(generation: generation)
            }
        }
    }

    private func listen(_ task: URLSessionWebSocketTask, generation: Int) {
        Task { @MainActor in
            do {
                while true {
                    let message = try await task.receive()
                    let data: Data?
                    switch message {
                    case .string(let text): data = text.data(using: .utf8)
                    case .data(let raw): data = raw
                    @unknown default: data = nil
                    }
                    if let data, let frame = try? JSONDecoder().decode(WsFrame.self, from: data) {
                        handle(frame)
                    }
                }
            } catch {
                guard generation == socketGeneration else { return }
                socketNote = "reconnecting"
                scheduleReconnect(generation: generation)
            }
        }
    }

    private func scheduleReconnect(generation: Int) {
        guard generation == socketGeneration else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, generation == self.socketGeneration else { return }
            self.startSocket()
        }
    }

    private func handle(_ frame: WsFrame) {
        switch frame.type {
        case "connected":
            socketNote = "live"
            scheduleRefresh()
        case "changed":
            socketNote = "live"
            scheduleRefresh()
        case "activity":
            socketNote = "live"
            updateAgent(frame.agentId) { agent in
                if let execution = frame.execution { agent.execution = execution }
                if let state = frame.state { agent.state = state }
                if let connection = frame.connection { agent.connection = connection }
                if let canStop = frame.canStop { agent.canStop = canStop }
            }
            if frame.agentId == selectedId { scheduleRefresh() }
        case "stream":
            socketNote = "live"
            updateAgent(frame.agentId) { agent in
                agent.liveText = frame.liveText
                if let execution = frame.execution { agent.execution = execution }
            }
        default:
            break
        }
    }

    private func updateAgent(_ id: String?, _ mutate: (inout Agent) -> Void) {
        guard let id, let index = agents.firstIndex(where: { $0.id == id }) else { return }
        var agent = agents[index]
        mutate(&agent)
        agents[index] = agent
    }

    // MARK: - Actions

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let agent = selectedAgent else { return }
        sending = true
        defer { sending = false }
        do {
            try await client.send(agentId: agent.id, text: trimmed, id: UUID().uuidString, mode: nil)
            drafts[agent.id] = ""
            scheduleRefresh()
        } catch {
            actionError = error.localizedDescription
        }
    }

    func cancelQueued(id: String) async {
        do {
            try await client.cancel(id: id)
            scheduleRefresh()
        } catch {
            actionError = error.localizedDescription
        }
    }

    func retryMessage(id: String) async {
        do {
            try await client.retry(id: id)
            scheduleRefresh()
        } catch {
            actionError = error.localizedDescription
        }
    }

    func stopTurn() async {
        guard let agent = selectedAgent else { return }
        do {
            try await client.stop(agentId: agent.id)
            scheduleRefresh()
        } catch {
            actionError = error.localizedDescription
        }
    }

    func checkRunners() async {
        do {
            try await client.refreshConnections()
            scheduleRefresh()
        } catch {
            actionError = error.localizedDescription
        }
    }

    func createDeviceLink() async -> DeviceLink? {
        do {
            return try await client.deviceLink()
        } catch {
            actionError = error.localizedDescription
            return nil
        }
    }

    func detail(for event: LiveEvent) async -> EventDetail? {
        if let cached = eventCache[event.id] { return cached }
        do {
            let detail = try await client.eventDetail(agentId: event.agentId ?? selectedId, id: event.id)
            eventCache[event.id] = detail
            return detail
        } catch {
            actionError = error.localizedDescription
            return nil
        }
    }

    func signOut(message: String? = nil) {
        pollTask?.cancel()
        pollTask = nil
        debounceTask?.cancel()
        socketGeneration += 1
        socketTask?.cancel(with: .goingAway, reason: nil)
        socketTask = nil
        Task { await client.signOut() }
        KeychainStore.delete()
        UserDefaults.standard.removeObject(forKey: "teamroom.baseURL")
        agents = []
        selectedId = ""
        drafts = [:]
        eventCache = [:]
        revision = 0
        socketNote = "offline"
        syncError = nil
        pairingError = message
        phase = .pairing
    }
}
