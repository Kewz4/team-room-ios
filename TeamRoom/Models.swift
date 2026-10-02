import Foundation

/// One pre-paid wallet. A DeepSeek account can hold several, one per currency.
struct AgentWallet: Codable, Hashable {
    var currency: String?
    var total: String?
    var granted: String?
    var toppedUp: String?

    var hasAmount: Bool {
        !(total ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    var displayAmount: String? {
        guard let raw = total?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        return AgentWallet.money(raw, currency)
    }

    /// "$4.32" when the currency code is known, otherwise the raw amount with its code.
    static func money(_ raw: String, _ currency: String?) -> String {
        let code = (currency ?? "").trimmingCharacters(in: .whitespaces).uppercased()
        guard let value = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) else {
            return code.isEmpty ? raw : "\(raw) \(code)"
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code.isEmpty ? "USD" : code
        return formatter.string(from: value as NSDecimalNumber) ?? (code.isEmpty ? raw : "\(raw) \(code)")
    }
}

/// DeepSeek accounts are pre-paid, so the bridge reports an account balance instead of usage windows.
struct AgentBalance: Codable, Hashable {
    var available: Bool?
    var currency: String?
    var total: String?
    var granted: String?
    var toppedUp: String?
    var source: String?
    var updatedAt: String?
    var reason: String?
    var wallets: [AgentWallet]?
}

extension AgentBalance {
    var hasAmount: Bool {
        !(total ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    var displayAmount: String? {
        guard let raw = total?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        return AgentWallet.money(raw, currency)
    }

    /// Every wallet the account holds, primary first; the primary amount alone when none are listed.
    var walletAmounts: [String] {
        let listed = (wallets ?? []).compactMap { $0.displayAmount }
        if !listed.isEmpty { return listed }
        return displayAmount.map { [$0] } ?? []
    }
}

struct AgentUsage: Codable, Hashable {
    var activity: String?
    var weekly: Double?
    var fiveHour: Double?
    var updatedAt: String?
    var source: String?
    var resetAt: String?
    var balance: AgentBalance?

    private enum CodingKeys: String, CodingKey {
        case activity, weekly, fiveHour, updatedAt, source, resetAt, balance
    }
}

extension AgentUsage {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        activity = try values.decodeIfPresent(String.self, forKey: .activity)
        weekly = try values.decodeIfPresent(Double.self, forKey: .weekly)
        fiveHour = try values.decodeIfPresent(Double.self, forKey: .fiveHour)
        source = try values.decodeIfPresent(String.self, forKey: .source)
        resetAt = try values.decodeIfPresent(String.self, forKey: .resetAt)
        balance = try values.decodeIfPresent(AgentBalance.self, forKey: .balance)
        if !values.contains(.updatedAt) {
            updatedAt = nil
        } else if try values.decodeNil(forKey: .updatedAt) {
            updatedAt = nil
        } else if let timestamp = try? values.decode(String.self, forKey: .updatedAt) {
            updatedAt = timestamp
        } else {
            // Older bridges returned fs.stat's Unix epoch milliseconds, including fractions.
            let milliseconds = try values.decode(Double.self, forKey: .updatedAt)
            guard milliseconds.isFinite, milliseconds >= -62135596800000,
                  milliseconds < 253402300800000 else {
                throw DecodingError.dataCorruptedError(forKey: .updatedAt, in: values,
                    debugDescription: "Usage timestamp is outside the supported ISO date range.")
            }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            updatedAt = formatter.string(from: Date(timeIntervalSince1970: milliseconds / 1000))
        }
    }
}

struct AgentConnection: Codable, Hashable {
    var ready: Bool
    var reason: String?
    var checkedAt: String?
}

struct ExecutionChild: Codable, Hashable, Identifiable {
    var id: String
    var label: String?
    var state: String
    var updatedAt: String?
}

struct Execution: Codable, Hashable {
    var phase: String?
    var label: String?
    var since: String?
    var children: [ExecutionChild]?
}

/// Transcript message or hub delivery-queue item; the optional fields cover both shapes.
struct ChatMessage: Codable, Hashable, Identifiable {
    var id: String
    var role: String?
    var phase: String?
    var text: String?
    var time: String?
    var agentId: String?
    var createdAt: String?
    var sentAt: String?
    var completedAt: String?
    var state: String?
    var error: String?
    var retriedAs: String?
    var editedAt: String?
    var redacted: Bool?
    var images: [EventImage]?
    /// The bridge cut a very long message; `fullLength` is the original size, loaded on demand.
    var truncated: Bool?
    var fullLength: Int?
}

struct DeliveryHistory: Codable { var messages: [ChatMessage] }
struct PushStatus: Codable {
    var configured: Bool
    var registered: Bool?
    var reason: String?
    var topic: String?
}

struct TaskStatus: Codable, Hashable {
    var kind: String
    var label: String
    var detail: String?
    var at: String?
    var eventId: String?
    var runId: String?
}

struct LiveEvent: Codable, Hashable, Identifiable {
    var id: String
    var kind: String
    var title: String
    var time: String?
    var updatedAt: String?
    var status: String?
    var action: String?
    var detailPreview: String?
    var detailVersion: Int?
    var agentId: String?
    var images: [EventImage]?
}

struct EventImage: Codable, Hashable, Identifiable {
    var id: String
    var label: String?
    var status: String?
    var mime: String?
}

struct EventDetail: Codable, Hashable {
    var id: String
    var kind: String?
    var title: String?
    var time: String?
    var updatedAt: String?
    var status: String?
    var detail: String?
    var detailPreview: String?
    var images: [EventImage]?
}

struct PromptOption: Codable, Hashable, Identifiable {
    var id: String { label }
    var label: String
    var description: String?
}

struct PromptQuestion: Codable, Hashable, Identifiable {
    var id: String
    var header: String?
    var question: String
    var isOther: Bool?
    var isSecret: Bool?
    var options: [PromptOption]?
}

/// A pending decision from a teammate: a question, command/file approval, or permission request.
struct AgentPrompt: Codable, Hashable, Identifiable {
    var id: String
    var kind: String
    var title: String?
    var detail: String?
    var command: String?
    var cwd: String?
    var reason: String?
    var createdAt: String?
    var allowSession: Bool?
    var questions: [PromptQuestion]?
}

struct PromptAnswerValue: Codable, Hashable {
    var answers: [String]
}

struct PromptAnswer: Codable {
    var decision: String? = nil
    var scope: String? = nil
    var deny: Bool? = nil
    var decline: Bool? = nil
    var answers: [String: PromptAnswerValue]? = nil
}

struct AgentHold: Codable, Hashable {
    var manual: Bool?
    var until: String?
    var reason: String?
}

/// Kewz's hard usage stop for an account (e.g. Polaris stops at 85% of 5 hours / 95% weekly).
struct AgentQuota: Codable, Hashable {
    var fiveHourStop: Double?
    var weeklyStop: Double?
    var held: Bool?
    var reason: String?
    var resumesAt: String?
}

struct MessagePreview: Codable, Hashable {
    var role: String?
    var text: String?
    var time: String?
}

struct Agent: Codable, Hashable, Identifiable {
    var id: String
    var label: String
    /// Worker display name (Nova, Atlas, Scout, Flint, Sage) from bridge API v2; `label` on older bridges.
    var name: String?
    var worker: String?
    var rev: Int?
    var lastMessage: MessagePreview?
    var liveLength: Int?
    var hold: AgentHold?
    var waiting: Int?
    var quota: AgentQuota?
    var account: String?
    var role: String?
    var provider: String?
    var modelLabel: String?
    var effort: String?
    var sessionId: String?
    var state: String?
    var statusSummary: TaskStatus?
    var execution: Execution?
    var activity: String?
    var connection: AgentConnection?
    var usage: AgentUsage?
    var lastEventAt: String?
    var source: String?
    var canStop: Bool?
    var liveText: String?
    var turnId: String?
    var queue: [ChatMessage]?
    var messages: [ChatMessage]?
    var events: [LiveEvent]?
    var prompts: [AgentPrompt]?
    var loading: Bool?
    var error: String?

    var displayName: String { (name?.isEmpty == false ? name : nil) ?? label }

    var taskStatus: TaskStatus {
        if let prompt = prompts?.first {
            return TaskStatus(kind: "needs_input", label: "Needs your input", detail: prompt.title, at: prompt.createdAt, eventId: "\(id):prompt:\(prompt.id)")
        }
        if connection?.ready == false { return TaskStatus(kind: "disconnected", label: "Connection lost", detail: connection?.reason) }
        if state == "working" { return TaskStatus(kind: "working", label: "Working", detail: execution?.label ?? activity, at: execution?.since) }
        if let statusSummary { return statusSummary }
        // v0.4 bridges already expose explicit completion events. Keep feedback useful
        // without requiring a bridge restart while another teammate is still working.
        if state == "idle" {
            let queued = (queue ?? []).last { ["queued", "waiting_busy", "waiting_connection", "sending", "streaming"].contains($0.state ?? "") }
            if let queued { return TaskStatus(kind: "queued", label: "Queued", detail: "Your message is waiting to start.", at: queued.createdAt, runId: queued.id) }
            let terminal = (events ?? []).filter {
                ["Reply complete", "Turn completed", "Turn failed", "Message failed", "Turn stopped"].contains($0.title)
            }.max { (TimeFormat.date($0.time) ?? .distantPast) < (TimeFormat.date($1.time) ?? .distantPast) }
            let failure = (queue ?? []).filter { ["failed", "interrupted"].contains($0.state ?? "") }.max {
                (TimeFormat.date($0.completedAt ?? $0.createdAt) ?? .distantPast) < (TimeFormat.date($1.completedAt ?? $1.createdAt) ?? .distantPast)
            }
            if let failure, (TimeFormat.date(failure.completedAt ?? failure.createdAt) ?? .distantPast)
                >= (TimeFormat.date(terminal?.time) ?? .distantPast).addingTimeInterval(-2) {
                let kind = failure.state ?? "failed"
                return TaskStatus(kind: kind, label: kind == "interrupted" ? "Interrupted" : "Failed", detail: failure.error,
                                  at: failure.completedAt ?? failure.createdAt, eventId: "\(id):run:\(failure.id):\(kind)", runId: failure.id)
            }
            if let terminal {
                let completed = ["Reply complete", "Turn completed"].contains(terminal.title)
                return TaskStatus(kind: completed ? "completed" : "failed", label: completed ? "Finished" : "Failed",
                    detail: completed ? "The latest task finished. Open its conversation for the result." : terminal.detailPreview,
                    at: terminal.time, eventId: "\(id):event:\(terminal.id)")
            }
        }
        return TaskStatus(kind: state == "idle" ? "idle" : "unknown", label: state == "idle" ? "Ready" : "Checking activity", detail: "Refresh to see the latest task result.")
    }
}

extension Agent {
    private enum DecodeKeys: String, CodingKey {
        case id, label, name, worker, rev, lastMessage, liveLength, hold, waiting, quota, account, role, provider, modelLabel, effort,
             sessionId, state, statusSummary, execution, activity, connection, usage, lastEventAt, source, canStop, liveText,
             turnId, queue, messages, events, prompts, loading, error
    }

    /// Field-by-field decoding: a malformed optional field is dropped instead of hiding the whole teammate.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DecodeKeys.self)
        id = try c.decode(String.self, forKey: .id)
        let name = try? c.decodeIfPresent(String.self, forKey: .name)
        label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? name ?? id
        self.name = name
        worker = try? c.decodeIfPresent(String.self, forKey: .worker)
        rev = try? c.decodeIfPresent(Int.self, forKey: .rev)
        lastMessage = try? c.decodeIfPresent(MessagePreview.self, forKey: .lastMessage)
        liveLength = try? c.decodeIfPresent(Int.self, forKey: .liveLength)
        hold = try? c.decodeIfPresent(AgentHold.self, forKey: .hold)
        waiting = try? c.decodeIfPresent(Int.self, forKey: .waiting)
        quota = try? c.decodeIfPresent(AgentQuota.self, forKey: .quota)
        account = try? c.decodeIfPresent(String.self, forKey: .account)
        role = try? c.decodeIfPresent(String.self, forKey: .role)
        provider = try? c.decodeIfPresent(String.self, forKey: .provider)
        modelLabel = try? c.decodeIfPresent(String.self, forKey: .modelLabel)
        effort = try? c.decodeIfPresent(String.self, forKey: .effort)
        sessionId = try? c.decodeIfPresent(String.self, forKey: .sessionId)
        state = try? c.decodeIfPresent(String.self, forKey: .state)
        statusSummary = try? c.decodeIfPresent(TaskStatus.self, forKey: .statusSummary)
        execution = try? c.decodeIfPresent(Execution.self, forKey: .execution)
        activity = try? c.decodeIfPresent(String.self, forKey: .activity)
        connection = try? c.decodeIfPresent(AgentConnection.self, forKey: .connection)
        usage = try? c.decodeIfPresent(AgentUsage.self, forKey: .usage)
        lastEventAt = try? c.decodeIfPresent(String.self, forKey: .lastEventAt)
        source = try? c.decodeIfPresent(String.self, forKey: .source)
        canStop = try? c.decodeIfPresent(Bool.self, forKey: .canStop)
        liveText = try? c.decodeIfPresent(String.self, forKey: .liveText)
        turnId = try? c.decodeIfPresent(String.self, forKey: .turnId)
        queue = c.contains(.queue) ? c.lossy(ChatMessage.self, forKey: .queue) : nil
        messages = c.contains(.messages) ? c.lossy(ChatMessage.self, forKey: .messages) : nil
        events = c.contains(.events) ? c.lossy(LiveEvent.self, forKey: .events) : nil
        prompts = c.contains(.prompts) ? c.lossy(AgentPrompt.self, forKey: .prompts) : nil
        loading = try? c.decodeIfPresent(Bool.self, forKey: .loading)
        error = try? c.decodeIfPresent(String.self, forKey: .error)
    }
}

struct StateResponse: Codable {
    var mediaPreviews: Bool?
    var revision: Int?
    var serverTime: String?
    var startedAt: String?
    var remoteUrl: String?
    var freeMemoryGb: Double?
    var agents: [Agent]
}

struct HealthResponse: Codable {
    var ok: Bool?
    var uiBuild: String?
    var mediaPreviews: Bool?
}

struct SessionStatus: Codable {
    var authenticated: Bool
    var local: Bool?
}

struct DeviceLink: Codable {
    var url: String?
    var localUrl: String?
    var expires: Double?
}

struct ApiError: Codable {
    var error: String?
}

struct WsFrame: Codable {
    var type: String
    var revision: Int?
    var agentId: String?
    var liveText: String?
    var execution: Execution?
    var state: String?
    var connection: AgentConnection?
    var canStop: Bool?
}

enum TimeFormat {
    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return iso.date(from: value) ?? isoPlain.date(from: value)
    }

    static func relative(_ value: String?) -> String {
        guard let date = date(value) else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
