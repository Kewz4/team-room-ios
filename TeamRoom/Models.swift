import Foundation

struct AgentUsage: Codable, Hashable {
    var activity: String?
    var weekly: Double?
    var fiveHour: Double?
    var updatedAt: String?
    var source: String?
    var resetAt: String?
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

struct Agent: Codable, Hashable, Identifiable {
    var id: String
    var label: String
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
