import Foundation

struct ClientError: LocalizedError {
    var status: Int?
    var message: String

    init(status: Int? = nil, message: String) {
        self.status = status
        self.message = message
    }

    var errorDescription: String? { message }
    var isOffline: Bool { status == nil }
}

enum ResponseDecoder {
    static func decode<T: Decodable>(_ type: T.Type, from data: Data, endpoint: URL) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            var keys: [CodingKey] = []
            switch error {
            case DecodingError.typeMismatch(_, let context),
                 DecodingError.valueNotFound(_, let context),
                 DecodingError.dataCorrupted(let context): keys = context.codingPath
            case DecodingError.keyNotFound(let key, let context): keys = context.codingPath + [key]
            default: break
            }
            let field = keys.reduce("") { path, key in
                if let index = key.intValue { return path + "[\(index)]" }
                // Do not echo arbitrary dictionary keys, response bodies or decoder descriptions.
                let safe = key.stringValue.range(of: "^[A-Za-z][A-Za-z0-9_]{0,63}$", options: .regularExpression) != nil
                let name = safe ? key.stringValue : "field"
                return path.isEmpty ? name : path + "." + name
            }
            let location = field.isEmpty ? "response" : field
            throw ClientError(message: "Unexpected response from \(endpoint.path) at \(location).")
        }
    }
}

/// HTTP client for the PC bridge. An actor, so requests and JSON decoding never run on the main thread.
actor TeamRoomClient {
    nonisolated let session: URLSession
    private(set) var baseURL: URL?
    private(set) var cookieToken: String?

    private struct Empty: Codable {}

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 90
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        // Revalidation is explicit (ETag / If-None-Match); never serve a stale cached conversation.
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: configuration)
    }

    func configure(baseURL: URL, cookie: String?) {
        self.baseURL = baseURL
        self.cookieToken = cookie
    }

    var origin: String? {
        guard let baseURL, let host = baseURL.host else { return nil }
        var value = "\(baseURL.scheme ?? "https")://\(host)"
        if let port = baseURL.port { value += ":\(port)" }
        return value
    }

    // MARK: - Auth

    func signIn(pairingToken: String) async throws -> String? {
        struct Body: Codable { var token: String }
        let url = try endpoint("/api/signin")
        _ = try await data(for: post(url, Body(token: pairingToken)))
        let storage = session.configuration.httpCookieStorage ?? HTTPCookieStorage.shared
        let cookie = storage.cookies(for: url)?.first(where: { $0.name == "kewz_session" })?.value
        if let cookie { cookieToken = cookie }
        return cookie
    }

    func signOut() async {
        if let request = try? post(endpoint("/api/signout"), Empty()) {
            _ = try? await data(for: request)
        }
        cookieToken = nil
    }

    func sessionStatus() async throws -> SessionStatus {
        try await perform(get(try endpoint("/api/session")), as: SessionStatus.self)
    }

    /// Checks a different origin with the same session cookie (used to move to the stable address).
    func sessionStatus(at origin: URL) async throws -> SessionStatus {
        var components = URLComponents(url: origin, resolvingAgainstBaseURL: false)
        components?.path = "/api/session"
        guard let url = components?.url else { throw ClientError(message: "Server URL is not valid.") }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let cookieToken { request.setValue("kewz_session=\(cookieToken)", forHTTPHeaderField: "Cookie") }
        return try await perform(request, as: SessionStatus.self)
    }

    // MARK: - State

    func health() async throws -> HealthResponse {
        try await perform(get(try endpoint("/api/health")), as: HealthResponse.self)
    }

    func state(agentId: String?) async throws -> StateResponse {
        let query = agentId.map { ["agentId": $0] } ?? [:]
        return try await perform(get(try endpoint("/api/state", query: query)), as: StateResponse.self)
    }

    func team() async throws -> TeamSnapshot {
        try await perform(get(try endpoint("/api/team")), as: TeamSnapshot.self)
    }

    /// Conversation for one teammate. Returns nil payload when the server answers 304 Not Modified.
    func conversation(agentId: String, etag: String?) async throws -> (payload: ConversationPayload?, etag: String?) {
        var request = get(try endpoint("/api/conversation", query: ["agentId": agentId]))
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, http) = try await exchange(request)
        let tag = http.value(forHTTPHeaderField: "ETag")
        if http.statusCode == 304 { return (nil, etag) }
        guard (200..<300).contains(http.statusCode) else { throw failure(http, data) }
        guard let url = request.url else { throw ClientError(message: "Server URL is not valid.") }
        return (try ResponseDecoder.decode(ConversationPayload.self, from: data, endpoint: url), tag)
    }

    func fullMessage(agentId: String, id: String) async throws -> FullMessage {
        try await perform(get(try endpoint("/api/transcript-message", query: ["agentId": agentId, "id": id])), as: FullMessage.self)
    }

    // MARK: - Team chat

    func room(limit: Int = 120) async throws -> RoomPage {
        try await perform(get(try endpoint("/api/room", query: ["limit": String(limit)])), as: RoomPage.self)
    }

    func ask(id: String, text: String) async throws -> RoomAskResponse {
        struct Body: Codable { var id: String; var text: String }
        return try await perform(post(try endpoint("/api/room/messages"), Body(id: id, text: text)), as: RoomAskResponse.self)
    }

    func stopAnswer(id: String) async throws {
        struct Body: Codable { var id: String }
        _ = try await data(for: post(try endpoint("/api/room/stop"), Body(id: id)))
    }

    func retryAnswer(id: String) async throws {
        struct Body: Codable { var id: String }
        _ = try await data(for: post(try endpoint("/api/room/retry"), Body(id: id)))
    }

    // MARK: - Board

    func progress(fresh: Bool = false) async throws -> ProgressReport {
        try await perform(get(try endpoint("/api/progress", query: fresh ? ["fresh": "1"] : [:])), as: ProgressReport.self)
    }

    // MARK: - Notes

    func notes() async throws -> NotesPage {
        try await perform(get(try endpoint("/api/notes", query: ["all": "1"])), as: NotesPage.self)
    }

    /// Saves a note; a 409 means the PC holds a newer copy, which is returned instead.
    func saveNote(_ note: Note) async throws -> NoteSaveResponse {
        struct Body: Codable { var id: String; var text: String; var pinned: Bool; var shared: Bool; var updatedAt: String }
        let request = try post(try endpoint("/api/notes"), Body(id: note.id, text: note.text, pinned: note.pinned == true, shared: note.shared == true, updatedAt: note.updatedAt))
        let (data, http) = try await exchange(request)
        guard let url = request.url else { throw ClientError(message: "Server URL is not valid.") }
        if (200..<300).contains(http.statusCode) || http.statusCode == 409 {
            return try ResponseDecoder.decode(NoteSaveResponse.self, from: data, endpoint: url)
        }
        throw failure(http, data)
    }

    func deleteNote(id: String, updatedAt: String) async throws {
        struct Body: Codable { var id: String; var updatedAt: String }
        _ = try await data(for: post(try endpoint("/api/notes/delete"), Body(id: id, updatedAt: updatedAt)))
    }

    // MARK: - Actions

    func send(agentId: String, text: String, id: String, mode: String? = nil) async throws {
        struct Body: Codable {
            var agentId: String
            var text: String
            var id: String
            var mode: String?
        }
        _ = try await data(for: post(try endpoint("/api/messages"), Body(agentId: agentId, text: text, id: id, mode: mode)))
    }

    func cancel(id: String) async throws {
        struct Body: Codable { var id: String }
        _ = try await data(for: post(try endpoint("/api/cancel-message"), Body(id: id)))
    }

    /// 1.1: push a queued message into the turn that is running now (steering).
    func steer(id: String) async throws {
        struct Body: Codable { var id: String }
        _ = try await data(for: post(try endpoint("/api/steer"), Body(id: id)))
    }

    func retry(id: String) async throws {
        struct Body: Codable { var id: String }
        _ = try await data(for: post(try endpoint("/api/retry"), Body(id: id)))
    }

    func deliveryHistory(agentId: String) async throws -> [ChatMessage] {
        let result = try await perform(get(try endpoint("/api/delivery-history", query: ["agentId": agentId])), as: DeliveryHistory.self)
        return result.messages
    }

    func delivery(id: String, agentId: String) async throws -> ChatMessage {
        try await perform(get(try endpoint("/api/message", query: ["id": id, "agentId": agentId])), as: ChatMessage.self)
    }

    func editDelivery(id: String, agentId: String, text: String) async throws {
        struct Body: Codable { var id: String; var agentId: String; var text: String }
        _ = try await data(for: post(try endpoint("/api/edit-message"), Body(id: id, agentId: agentId, text: text)))
    }

    func deleteDelivery(id: String, agentId: String) async throws {
        struct Body: Codable { var id: String; var agentId: String }
        _ = try await data(for: post(try endpoint("/api/delete-message"), Body(id: id, agentId: agentId)))
    }

    func restoreDelivery(id: String, agentId: String) async throws {
        struct Body: Codable { var id: String; var agentId: String }
        _ = try await data(for: post(try endpoint("/api/restore-message"), Body(id: id, agentId: agentId)))
    }

    func artifact(path: String) async throws -> Data {
        try await data(for: get(try endpoint("/api/artifact", query: ["path": path])))
    }

    func stop(agentId: String) async throws {
        struct Body: Codable { var agentId: String }
        _ = try await data(for: post(try endpoint("/api/stop"), Body(agentId: agentId)))
    }

    func refreshConnections() async throws {
        _ = try await data(for: post(try endpoint("/api/refresh-connections"), Empty()))
    }

    func deviceLink() async throws -> DeviceLink {
        try await perform(post(try endpoint("/api/device-link"), Empty()), as: DeviceLink.self)
    }

    func respond(agentId: String, promptId: String, answer: PromptAnswer) async throws {
        struct Body: Codable {
            var agentId: String
            var promptId: String
            var answer: PromptAnswer
        }
        _ = try await data(for: post(try endpoint("/api/prompt-response"), Body(agentId: agentId, promptId: promptId, answer: answer)))
    }

    func eventDetail(agentId: String, id: String) async throws -> EventDetail {
        let url = try endpoint("/api/event", query: ["agentId": agentId, "id": id])
        return try await perform(get(url), as: EventDetail.self)
    }

    func media(agentId: String, id: String) async throws -> Data {
        let url = try endpoint("/api/media", query: ["agentId": agentId, "id": id])
        return try await data(for: get(url))
    }

    // MARK: - Native push (kept for a future push-enabled signing profile)

    func pushStatus() async throws -> PushStatus {
        try await perform(get(try endpoint("/api/push/status")), as: PushStatus.self)
    }

    func registerPush(token: String, environment: String) async throws {
        struct Body: Codable { var token: String; var environment: String; var topic: String }
        _ = try await data(for: post(try endpoint("/api/push/register"), Body(token: token, environment: environment, topic: Bundle.main.bundleIdentifier ?? "com.kewz.teamroom")))
    }

    func unregisterPush() async {
        if let request = try? post(endpoint("/api/push/unregister"), Empty()) { _ = try? await data(for: request) }
    }

    func testPush() async throws {
        _ = try await data(for: post(try endpoint("/api/push/test"), Empty()))
    }

    // MARK: - App update

    /// GET /api/app-update. A 404, a failed request or JSON that does not decode all mean "nothing to offer".
    func appUpdate() async -> AppUpdateInfo? {
        guard let url = try? endpoint("/api/app-update"),
              let (data, http) = try? await exchange(get(url)),
              (200..<300).contains(http.statusCode) else { return nil }
        return try? JSONDecoder().decode(AppUpdateInfo.self, from: data)
    }

    // MARK: - Bark background notifications

    func barkStatus() async throws -> BarkStatus {
        try await perform(get(try endpoint("/api/bark")), as: BarkStatus.self)
    }

    func barkSetup(deviceKey: String, server: String?) async throws -> BarkSetupResponse {
        struct Body: Codable { var deviceKey: String; var server: String? }
        return try await perform(post(try endpoint("/api/bark/setup"), Body(deviceKey: deviceKey, server: server)), as: BarkSetupResponse.self)
    }

    func barkSettings() async throws -> BarkSettings {
        try await perform(get(try endpoint("/api/bark/settings")), as: BarkSettings.self)
    }

    func barkEvents(_ events: BarkEvents) async throws -> BarkStatus {
        struct Body: Codable { var events: BarkEvents }
        return try await perform(post(try endpoint("/api/bark/events"), Body(events: events)), as: BarkStatus.self)
    }

    func barkTest() async throws -> BarkTestResponse {
        var request = try post(try endpoint("/api/bark/test"), Empty())
        request.timeoutInterval = 25
        let (data, http) = try await exchange(request)
        guard let url = request.url else { throw ClientError(message: "Server URL is not valid.") }
        if (200..<300).contains(http.statusCode) || http.statusCode == 502 {
            return try ResponseDecoder.decode(BarkTestResponse.self, from: data, endpoint: url)
        }
        throw failure(http, data)
    }

    func barkRemove() async throws -> BarkStatus {
        try await perform(post(try endpoint("/api/bark/remove"), Empty()), as: BarkStatus.self)
    }

    // MARK: - Live socket

    func makeWebSocketRequest() throws -> URLRequest {
        guard let baseURL, let host = baseURL.host else {
            throw ClientError(message: "Server URL is not set.")
        }
        var components = URLComponents()
        components.scheme = baseURL.scheme == "http" ? "ws" : "wss"
        components.host = host
        components.port = baseURL.port
        components.path = "/live"
        components.queryItems = [URLQueryItem(name: "v", value: "2")]
        guard let url = components.url else {
            throw ClientError(message: "Server URL is not valid.")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        if let cookieToken {
            request.setValue("kewz_session=\(cookieToken)", forHTTPHeaderField: "Cookie")
        }
        return request
    }

    // MARK: - Plumbing

    private func endpoint(_ path: String, query: [String: String] = [:]) throws -> URL {
        guard let baseURL else {
            throw ClientError(message: "Server URL is not set.")
        }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ClientError(message: "Server URL is not valid.")
        }
        components.path = path
        components.queryItems = query.isEmpty ? nil : query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else {
            throw ClientError(message: "Server URL is not valid.")
        }
        return url
    }

    private func get(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let origin { request.setValue(origin, forHTTPHeaderField: "Origin") }
        if let cookieToken { request.setValue("kewz_session=\(cookieToken)", forHTTPHeaderField: "Cookie") }
        return request
    }

    private func post<T: Encodable>(_ url: URL, _ body: T) throws -> URLRequest {
        var request = get(url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func exchange(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw ClientError(message: Self.describe(error))
        } catch {
            throw ClientError(message: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ClientError(message: "No response from the Team Room server.")
        }
        return (data, http)
    }

    private func failure(_ http: HTTPURLResponse, _ data: Data) -> ClientError {
        let apiError = try? JSONDecoder().decode(ApiError.self, from: data)
        let fallback: String
        switch http.statusCode {
        case 401: fallback = "This device's session expired. Pair it again from the PC."
        case 421: fallback = "The PC does not recognize this address yet. Restart Team Room on the PC or pair again."
        case 502, 503, 504: fallback = "The PC is not answering through the tunnel right now."
        default: fallback = "Request failed (\(http.statusCode))."
        }
        return ClientError(status: http.statusCode, message: apiError?.error ?? fallback)
    }

    @discardableResult
    private func data(for request: URLRequest) async throws -> Data {
        let (data, http) = try await exchange(request)
        guard (200..<300).contains(http.statusCode) else { throw failure(http, data) }
        return data
    }

    private func perform<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let data = try await data(for: request)
        if type == Empty.self { return Empty() as! T }
        guard let endpoint = request.url else { throw ClientError(message: "Server URL is not valid.") }
        return try ResponseDecoder.decode(type, from: data, endpoint: endpoint)
    }

    static func describe(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet: return "This iPhone is offline."
        case .timedOut: return "The PC took too long to answer."
        case .cannotFindHost, .dnsLookupFailed: return "The Team Room address could not be found. Is the PC on and Tailscale running?"
        case .cannotConnectToHost, .networkConnectionLost: return "Could not reach the PC. It may be asleep or restarting."
        case .secureConnectionFailed, .serverCertificateUntrusted: return "The secure connection to the PC failed."
        case .cancelled: return "The request was cancelled."
        default: return error.localizedDescription
        }
    }
}
