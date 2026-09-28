import Foundation

struct ClientError: LocalizedError {
    var status: Int?
    var message: String

    init(status: Int? = nil, message: String) {
        self.status = status
        self.message = message
    }

    var errorDescription: String? { message }
}

actor TeamRoomClient {
    nonisolated let session: URLSession
    private(set) var baseURL: URL?
    private(set) var cookieToken: String?

    private struct Empty: Codable {}

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 90
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
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

    // MARK: - State

    func health() async throws -> HealthResponse {
        try await perform(get(try endpoint("/api/health")), as: HealthResponse.self)
    }

    func state(agentId: String?) async throws -> StateResponse {
        let query = agentId.map { ["agentId": $0] } ?? [:]
        return try await perform(get(try endpoint("/api/state", query: query)), as: StateResponse.self)
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

    func retry(id: String) async throws {
        struct Body: Codable { var id: String }
        _ = try await data(for: post(try endpoint("/api/retry"), Body(id: id)))
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
        guard let url = components.url else {
            throw ClientError(message: "Server URL is not valid.")
        }
        var request = URLRequest(url: url)
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

    @discardableResult
    private func data(for request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ClientError(message: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ClientError(message: "No response from the Team Room server.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let apiError = try? JSONDecoder().decode(ApiError.self, from: data)
            throw ClientError(status: http.statusCode, message: apiError?.error ?? "Request failed (\(http.statusCode)).")
        }
        return data
    }

    private func perform<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let data = try await data(for: request)
        if type == Empty.self { return Empty() as! T }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ClientError(message: "Unexpected response from the Team Room server.")
        }
    }
}
