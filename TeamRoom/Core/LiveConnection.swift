import Foundation
import Network

/// The live WebSocket (bridge protocol v2).
///
/// - Frames are received and JSON-decoded on a background task; only decoded frames hop to the main actor.
/// - Reconnects with exponential backoff and jitter, immediately when the network path comes back
///   (Wi-Fi <-> cellular), and when no frame (including the app-level pong) arrives for 50 seconds.
/// - Remembers subscriptions and foreground presence and re-sends them after every reconnect.
@MainActor
final class LiveConnection {
    enum Status: String {
        case offline, connecting, live, reconnecting
    }

    var onFrame: ((LiveFrame) -> Void)?
    var onStatus: ((Status) -> Void)?
    private(set) var status: Status = .offline

    private let client: TeamRoomClient
    private var task: URLSessionWebSocketTask?
    private var generation = 0
    private var attempts = 0
    private var reconnectTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var subscriptions: Set<String> = []
    private var foreground = true
    private var lastFrameAt = Date.distantPast
    private let pathMonitor = NWPathMonitor()
    private var pathSatisfied = true
    private var running = false

    init(client: TeamRoomClient) {
        self.client = client
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor [weak self] in self?.pathChanged(satisfied) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "teamroom.path"))
    }

    func start() {
        running = true
        foreground = true
        if task == nil || status == .offline { connect() }
    }

    /// Closes the socket (background or sign-out). Presence is sent first so the PC starts pushing alerts.
    func stop() {
        running = false
        send(["type": "presence", "foreground": false])
        generation += 1
        reconnectTask?.cancel()
        heartbeatTask?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        setStatus(.offline)
    }

    func reconnectNow() {
        guard running else { return }
        if status == .live, Date().timeIntervalSince(lastFrameAt) < 30 { return }
        attempts = 0
        connect()
    }

    func subscribe(_ agentId: String) {
        subscriptions.insert(agentId)
        send(["type": "subscribe", "agentId": agentId])
    }

    func unsubscribe(_ agentId: String) {
        subscriptions.remove(agentId)
        send(["type": "unsubscribe", "agentId": agentId])
    }

    func resync(_ agentId: String) {
        send(["type": "resync", "agentId": agentId])
    }

    func setForeground(_ value: Bool) {
        foreground = value
        send(["type": "presence", "foreground": value])
    }

    // MARK: - Connection

    private func connect() {
        generation += 1
        let current = generation
        reconnectTask?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        setStatus(attempts == 0 ? .connecting : .reconnecting)
        Task { [weak self] in
            guard let self else { return }
            do {
                let request = try await self.client.makeWebSocketRequest()
                guard current == self.generation else { return }
                let socket = self.client.session.webSocketTask(with: request)
                socket.maximumMessageSize = 8 * 1024 * 1024
                self.task = socket
                socket.resume()
                self.lastFrameAt = Date()
                self.receive(socket, generation: current)
                self.send(["type": "hello", "client": "ios", "build": Self.build, "foreground": self.foreground])
                for id in self.subscriptions { self.send(["type": "subscribe", "agentId": id]) }
                self.startHeartbeat(generation: current)
            } catch {
                self.socketFailed(generation: current)
            }
        }
    }

    private nonisolated func receive(_ socket: URLSessionWebSocketTask, generation: Int) {
        Task.detached(priority: .userInitiated) { [weak self] in
            let decoder = JSONDecoder()
            while true {
                let message: URLSessionWebSocketTask.Message
                do {
                    message = try await socket.receive()
                } catch {
                    await self?.socketFailed(generation: generation)
                    return
                }
                let data: Data
                switch message {
                case .string(let text): data = Data(text.utf8)
                case .data(let raw): data = raw
                @unknown default: continue
                }
                guard let frame = try? decoder.decode(LiveFrame.self, from: data) else { continue }
                await self?.deliver(frame, generation: generation)
            }
        }
    }

    private func deliver(_ frame: LiveFrame, generation current: Int) {
        guard current == generation else { return }
        lastFrameAt = Date()
        if frame.type == "connected" {
            attempts = 0
            setStatus(.live)
        }
        if frame.type == "pong" { return }
        onFrame?(frame)
    }

    /// Retires the failed socket once (its other callbacks are then ignored) and schedules a reconnect.
    private func socketFailed(generation current: Int) {
        guard current == generation else { return }
        generation += 1
        heartbeatTask?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard running, foreground, pathSatisfied else {
            setStatus(.offline)
            return
        }
        attempts += 1
        setStatus(.reconnecting)
        let base = min(30.0, pow(2.0, Double(min(attempts, 5))))
        let delay = base * Double.random(in: 0.7...1.3)
        let expected = generation
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, expected == self.generation else { return }
            self.connect()
        }
    }

    private func startHeartbeat(generation current: Int) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard let self, current == self.generation, !Task.isCancelled else { return }
                if Date().timeIntervalSince(self.lastFrameAt) > 50 {
                    // Silent socket (sleeping NAT, tunnel restart): drop it and reconnect.
                    self.socketFailed(generation: current)
                    return
                }
                self.send(["type": "ping"])
            }
        }
    }

    private func pathChanged(_ satisfied: Bool) {
        let was = pathSatisfied
        pathSatisfied = satisfied
        if satisfied && !was && running && foreground {
            attempts = 0
            connect()
        } else if !satisfied {
            setStatus(.offline)
        }
    }

    private func send(_ object: [String: Any]) {
        guard let task, let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { _ in }
    }

    private func setStatus(_ value: Status) {
        guard status != value else { return }
        status = value
        onStatus?(value)
    }

    static var build: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
