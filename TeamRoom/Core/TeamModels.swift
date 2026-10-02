import Foundation

// Models for bridge API v2 (Team Room 1.0): compact team summaries, per-teammate conversations, the team chat,
// the project board and Bark background notifications. Every collection decodes lossily: one malformed element
// is skipped instead of failing the whole response (a single bad field used to blank the entire app).

/// Decodes an array, dropping elements that fail to decode.
struct Lossy<Element: Decodable>: Decodable {
    var values: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Element] = []
        while !container.isAtEnd {
            if let value = try? container.decode(Element.self) {
                result.append(value)
            } else {
                _ = try? container.decode(Skip.self)
            }
        }
        values = result
    }

    private struct Skip: Decodable {}
}

extension KeyedDecodingContainer {
    func lossy<T: Decodable>(_ type: T.Type, forKey key: Key) -> [T] {
        (try? decodeIfPresent(Lossy<T>.self, forKey: key))?.values ?? []
    }
}

struct RelaySummary: Codable, Hashable {
    var enabled: Bool?
    var waiting: Int?
    var at: String?
    var paused: Bool?
}

struct Coordinator: Codable, Hashable, Identifiable {
    var name: String
    var label: String
    var role: String?
    var agentId: String?
    var available: Bool?
    var note: String?
    var answering: Bool?
    var id: String { name }
}

struct TeamSnapshot: Codable {
    var apiVersion: Int?
    var revision: Int?
    var serverTime: String?
    var startedAt: String?
    var publicOrigins: [String]?
    var relay: RelaySummary?
    var coordinators: [Coordinator]
    var agents: [Agent]

    private enum CodingKeys: String, CodingKey {
        case apiVersion, revision, serverTime, startedAt, publicOrigins, relay, coordinators, agents
    }

    init(apiVersion: Int? = 2, revision: Int? = nil, serverTime: String? = nil, startedAt: String? = nil,
         publicOrigins: [String]? = nil, relay: RelaySummary? = nil, coordinators: [Coordinator] = [], agents: [Agent] = []) {
        self.apiVersion = apiVersion
        self.revision = revision
        self.serverTime = serverTime
        self.startedAt = startedAt
        self.publicOrigins = publicOrigins
        self.relay = relay
        self.coordinators = coordinators
        self.agents = agents
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apiVersion = try? c.decodeIfPresent(Int.self, forKey: .apiVersion)
        revision = try? c.decodeIfPresent(Int.self, forKey: .revision)
        serverTime = try? c.decodeIfPresent(String.self, forKey: .serverTime)
        startedAt = try? c.decodeIfPresent(String.self, forKey: .startedAt)
        publicOrigins = try? c.decodeIfPresent([String].self, forKey: .publicOrigins)
        relay = try? c.decodeIfPresent(RelaySummary.self, forKey: .relay)
        coordinators = c.lossy(Coordinator.self, forKey: .coordinators)
        agents = c.lossy(Agent.self, forKey: .agents)
    }
}

struct ConversationPayload: Codable {
    var agentId: String
    var rev: Int?
    var messages: [ChatMessage]
    var events: [LiveEvent]
    var liveText: String?
    var queue: [ChatMessage]
    var prompts: [AgentPrompt]
    var loading: Bool?
    var error: String?

    private enum CodingKeys: String, CodingKey {
        case agentId, rev, messages, events, liveText, queue, prompts, loading, error
    }

    init(agentId: String, rev: Int? = nil, messages: [ChatMessage] = [], events: [LiveEvent] = [], liveText: String? = nil,
         queue: [ChatMessage] = [], prompts: [AgentPrompt] = [], loading: Bool? = nil, error: String? = nil) {
        self.agentId = agentId
        self.rev = rev
        self.messages = messages
        self.events = events
        self.liveText = liveText
        self.queue = queue
        self.prompts = prompts
        self.loading = loading
        self.error = error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        agentId = try c.decode(String.self, forKey: .agentId)
        rev = try? c.decodeIfPresent(Int.self, forKey: .rev)
        messages = c.lossy(ChatMessage.self, forKey: .messages)
        events = c.lossy(LiveEvent.self, forKey: .events)
        liveText = try? c.decodeIfPresent(String.self, forKey: .liveText)
        queue = c.lossy(ChatMessage.self, forKey: .queue)
        prompts = c.lossy(AgentPrompt.self, forKey: .prompts)
        loading = try? c.decodeIfPresent(Bool.self, forKey: .loading)
        error = try? c.decodeIfPresent(String.self, forKey: .error)
    }
}

struct FullMessage: Codable {
    var id: String
    var role: String?
    var time: String?
    var text: String?
}

// MARK: - Team chat

struct ClaimCandidate: Codable, Hashable, Identifiable {
    var name: String
    var label: String?
    var eligible: Bool?
    var note: String?
    var id: String { name }
}

struct RoomClaim: Codable, Hashable {
    var responder: String?
    var reason: String?
    var considered: [ClaimCandidate]?
    var at: String?
}

struct RoomAttempt: Codable, Hashable {
    var responder: String?
    var state: String?
    var error: String?
    var at: String?
}

struct RoomMessage: Codable, Hashable, Identifiable {
    var id: String
    var role: String
    var text: String?
    var createdAt: String?
    var startedAt: String?
    var completedAt: String?
    var state: String?
    var replyTo: String?
    var responder: String?
    var claim: RoomClaim?
    var attempts: [RoomAttempt]?
    var activity: String?
    var error: String?
    var model: String?
    var mention: String?

    var isUser: Bool { role == "user" }
    var isInProgress: Bool { ["queued", "answering"].contains(state ?? "") }
    var isFailure: Bool { ["failed", "stopped", "interrupted"].contains(state ?? "") }
    /// Hand-overs and direct requests are worth showing; "first available" is not.
    var claimWorthShowing: Bool {
        guard let reason = claim?.reason, !reason.isEmpty else { return false }
        return !reason.contains("as the first available coordinator")
    }
}

struct RoomPage: Codable {
    var messages: [RoomMessage]
    var coordinators: [Coordinator]

    private enum CodingKeys: String, CodingKey { case messages, coordinators }

    init(messages: [RoomMessage] = [], coordinators: [Coordinator] = []) {
        self.messages = messages
        self.coordinators = coordinators
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        messages = c.lossy(RoomMessage.self, forKey: .messages)
        coordinators = c.lossy(Coordinator.self, forKey: .coordinators)
    }
}

struct RoomAskResponse: Codable {
    var question: RoomMessage?
    var answer: RoomMessage?
}

// MARK: - Board

struct ProjectInfo: Codable, Hashable {
    var name: String?
    var summary: String?
    var scope: String?
}

struct PlanInfo: Codable, Hashable {
    var exists: Bool?
    var updatedAt: String?
    var updatedBy: String?
    var file: String?
}

struct OverallProgress: Codable, Hashable {
    var percent: Int
    var label: String?
    var method: String?
}

struct Goal: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var summary: String?
    var owner: String?
    var ownerName: String?
    var status: String?
    var statusLabel: String?
    var percent: Int?
    var method: String?
    var metricLabel: String?
    var milestoneCount: Int?
    var doneMilestones: Int?
    var note: String?
}

struct Milestone: Codable, Hashable, Identifiable {
    var id: String
    var goal: String?
    var title: String
    var owner: String?
    var ownerName: String?
    var status: String?
    var percent: Int?
    var method: String?
    var note: String?
    var evidence: String?
    var updatedAt: String?
}

struct PlanTask: Codable, Hashable, Identifiable {
    var id: String
    var milestone: String?
    var title: String
    var owner: String?
    var ownerName: String?
    var status: String?
    var blockedBy: String?
    var note: String?
    var evidence: String?
    var updatedAt: String?
}

struct Decision: Codable, Hashable, Identifiable {
    var id: String
    var kind: String?
    var agentId: String?
    var title: String
    var detail: String?
    var owner: String?
    var status: String?
    var evidence: String?
    var createdAt: String?
}

struct RegionCount: Codable, Hashable, Identifiable {
    var region: String
    var label: String?
    var count: Int
    var target: Int?
    var source: String?
    var id: String { region }
}

struct EngineMilestone: Codable, Hashable, Identifiable {
    var id: String
    var track: String?
    var unitTests: Int?
    var runtimeVerified: Bool?
    var independentReview: String?
    var scope: String?
    var evidence: String?
}

struct Metric: Codable, Hashable {
    var value: Int
    var target: Int
    var unit: String?
}

struct LoreMetric: Codable, Hashable {
    var value: Int
    var target: Int
    var unit: String?
    var byRegion: [RegionCount]?
}

struct EngineMetric: Codable, Hashable {
    var value: Int
    var target: Int
    var unit: String?
    var rows: [EngineMilestone]?
}

struct BoardMetrics: Codable, Hashable {
    var loreQuests: LoreMetric?
    var regionsWithQuests: Metric?
    var engineMilestones: EngineMetric?
}

struct WorkUnit: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var from: String?
    var to: String?
    var agentId: String?
    var toName: String?
    var kind: String?
    var state: String
    var reason: String?
    var error: String?
    var createdAt: String?
    var startedAt: String?
    var completedAt: String?
}

struct WorkColumns: Codable, Hashable {
    var queued: [WorkUnit]?
    var blocked: [WorkUnit]?
    var running: [WorkUnit]?
    var done: [WorkUnit]?
    var failed: [WorkUnit]?

    func units(_ state: String) -> [WorkUnit] {
        switch state {
        case "queued": return queued ?? []
        case "blocked": return blocked ?? []
        case "running": return running ?? []
        case "done": return done ?? []
        case "failed": return failed ?? []
        default: return []
        }
    }
}

struct WorkBoard: Codable, Hashable {
    var columns: WorkColumns
    var totals: [String: Int]?
}

struct ActivityPoint: Codable, Hashable, Identifiable {
    var day: String
    var agentId: String
    var name: String?
    var finished: Int
    var failed: Int?
    var hours: Double
    var id: String { day + "|" + agentId }
}

struct WorkLane: Codable, Hashable, Identifiable {
    var agentId: String
    var name: String
    var state: String?
    var account: String?
    var now: String?
    var running: String?
    var queued: Int?
    var blocked: Int?
    var finishedToday: Int?
    var hoursToday: Double?
    var hold: AgentHold?
    var id: String { agentId }
}

struct ProgressReport: Codable {
    var generatedAt: String?
    var project: ProjectInfo?
    var plan: PlanInfo?
    var overall: OverallProgress
    var goals: [Goal]
    var milestones: [Milestone]
    var tasks: [PlanTask]
    var decisions: [Decision]
    var metrics: BoardMetrics?
    var work: WorkBoard?
    var series: [ActivityPoint]
    var lanes: [WorkLane]

    private enum CodingKeys: String, CodingKey {
        case generatedAt, project, plan, overall, goals, milestones, tasks, decisions, metrics, work, series, lanes
    }

    init(generatedAt: String? = nil, project: ProjectInfo? = nil, plan: PlanInfo? = nil, overall: OverallProgress = OverallProgress(percent: 0),
         goals: [Goal] = [], milestones: [Milestone] = [], tasks: [PlanTask] = [], decisions: [Decision] = [],
         metrics: BoardMetrics? = nil, work: WorkBoard? = nil, series: [ActivityPoint] = [], lanes: [WorkLane] = []) {
        self.generatedAt = generatedAt
        self.project = project
        self.plan = plan
        self.overall = overall
        self.goals = goals
        self.milestones = milestones
        self.tasks = tasks
        self.decisions = decisions
        self.metrics = metrics
        self.work = work
        self.series = series
        self.lanes = lanes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try? c.decodeIfPresent(String.self, forKey: .generatedAt)
        project = try? c.decodeIfPresent(ProjectInfo.self, forKey: .project)
        plan = try? c.decodeIfPresent(PlanInfo.self, forKey: .plan)
        overall = (try? c.decodeIfPresent(OverallProgress.self, forKey: .overall)) ?? OverallProgress(percent: 0)
        goals = c.lossy(Goal.self, forKey: .goals)
        milestones = c.lossy(Milestone.self, forKey: .milestones)
        tasks = c.lossy(PlanTask.self, forKey: .tasks)
        decisions = c.lossy(Decision.self, forKey: .decisions)
        metrics = try? c.decodeIfPresent(BoardMetrics.self, forKey: .metrics)
        work = try? c.decodeIfPresent(WorkBoard.self, forKey: .work)
        series = c.lossy(ActivityPoint.self, forKey: .series)
        lanes = c.lossy(WorkLane.self, forKey: .lanes)
    }
}

// MARK: - Bark

struct BarkEvents: Codable, Hashable {
    var needs_input: Bool?
    var room: Bool?
    var failed: Bool?
    var mine: Bool?
    var completed: Bool?
}

struct BarkResult: Codable, Hashable {
    var at: String?
    var ok: Bool?
    var kind: String?
    var error: String?
}

struct BarkStatus: Codable, Hashable {
    var configured: Bool
    var server: String?
    var deviceHint: String?
    var events: BarkEvents?
    var verifiedAt: String?
    var lastResult: BarkResult?
    var appStore: String?
}

struct BarkSettings: Codable, Hashable {
    var algorithm: String
    var mode: String
    var padding: String?
    var key: String
    var iv: String?
}

struct BarkSetupResponse: Codable {
    var status: BarkStatus
    var settings: BarkSettings
}

struct BarkTestResponse: Codable {
    var ok: Bool?
    var error: String?
    var status: BarkStatus?
}

// MARK: - Notes

/// One of Kewz's personal notes. Private on the PC unless `shared` (then the coordinators can read it).
struct Note: Codable, Hashable, Identifiable {
    var id: String
    var text: String
    var title: String?
    var pinned: Bool?
    var shared: Bool?
    var createdAt: String?
    var updatedAt: String
    var deleted: Bool?
    /// Local only: an edit or delete that has not reached the PC yet.
    var pendingSync: Bool?

    var displayTitle: String {
        let first = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let cleaned = first.replacingOccurrences(of: "^#+[ \\t]*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "New note" : cleaned
    }

    var preview: String {
        let lines = text.split(whereSeparator: \.isNewline).dropFirst()
        return lines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}

struct NotesPage: Codable {
    var notes: [Note]

    private enum CodingKeys: String, CodingKey { case notes }

    init(notes: [Note] = []) { self.notes = notes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        notes = c.lossy(Note.self, forKey: .notes)
    }
}

struct NoteSaveResponse: Codable {
    var note: Note
    var stale: Bool?
}

// MARK: - Live socket v2

struct LiveFrame: Decodable {
    var type: String
    var revision: Int?
    var apiVersion: Int?
    var revs: [String: Int]?
    var agents: [Agent]?
    var agentId: String?
    var execution: Execution?
    var state: String?
    var connection: AgentConnection?
    var canStop: Bool?
    var base: Int?
    var append: String?
    var reset: Bool?
    var text: String?
    var message: RoomMessage?

    private enum CodingKeys: String, CodingKey {
        case type, revision, apiVersion, revs, agents, agentId, execution, state, connection, canStop, base, append, reset, text, message
    }

    init(type: String) { self.type = type }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        revision = try? c.decodeIfPresent(Int.self, forKey: .revision)
        apiVersion = try? c.decodeIfPresent(Int.self, forKey: .apiVersion)
        revs = try? c.decodeIfPresent([String: Int].self, forKey: .revs)
        if c.contains(.agents) { agents = c.lossy(Agent.self, forKey: .agents) }
        agentId = try? c.decodeIfPresent(String.self, forKey: .agentId)
        execution = try? c.decodeIfPresent(Execution.self, forKey: .execution)
        state = try? c.decodeIfPresent(String.self, forKey: .state)
        connection = try? c.decodeIfPresent(AgentConnection.self, forKey: .connection)
        canStop = try? c.decodeIfPresent(Bool.self, forKey: .canStop)
        base = try? c.decodeIfPresent(Int.self, forKey: .base)
        append = try? c.decodeIfPresent(String.self, forKey: .append)
        reset = try? c.decodeIfPresent(Bool.self, forKey: .reset)
        text = try? c.decodeIfPresent(String.self, forKey: .text)
        message = try? c.decodeIfPresent(RoomMessage.self, forKey: .message)
    }
}

enum StreamDelta {
    /// Applies a v2 stream frame to the text the app holds; nil means the frames are out of step and a resync is needed.
    static func apply(_ frame: LiveFrame, to current: String) -> String? {
        if frame.reset == true { return frame.text ?? "" }
        guard let base = frame.base else { return nil }
        // The bridge counts JavaScript string length, i.e. UTF-16 code units.
        guard current.utf16.count == base else { return nil }
        return current + (frame.append ?? "")
    }
}
