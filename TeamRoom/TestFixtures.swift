#if DEBUG
import SwiftUI
import UIKit

/// Populated fixtures for UI tests and the screenshot QA run: the real team (names, accounts, models), realistic
/// states and the project's real board numbers, so every screen is captured the way it looks with live data.
enum TestFixtures {
    static let now = "2026-10-02T03:30:00.000Z"

    static var deliveries: [ChatMessage] {
        [ChatMessage(id: "fixture-failed", text: "Original request that failed delivery", agentId: "claude-assets", createdAt: "2026-10-01T20:00:00Z", state: "failed", error: "Session limit reached")]
    }

    static var image: UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 320, height: 240)).image { context in
            for y in 0..<6 {
                for x in 0..<8 {
                    ((x + y) % 2 == 0 ? UIColor.systemTeal : UIColor.systemOrange).setFill()
                    context.fill(CGRect(x: x * 40, y: y * 40, width: 40, height: 40))
                }
            }
        }
    }

    @MainActor static func load(_ model: AppModel) {
        let arguments = ProcessInfo.processInfo.arguments
        model.baseURLString = "https://teamroom.example.ts.net:8443"
        model.team.agents = agents
        model.team.coordinators = coordinators
        model.team.relay = RelaySummary(enabled: true, waiting: 77, at: now, paused: false)
        model.team.lastSync = Date()
        model.room.coordinators = coordinators
        model.room.messages = arguments.contains("-ui-empty-chat") ? [] : roomMessages
        model.room.loaded = true
        model.board.report = report
        model.board.loadedAt = Date()
        model.notes.notes = notes
        model.notes.loaded = true
        model.bark = BarkStatus(configured: true, server: "https://api.day.app", deviceHint: "…2gRA",
                                events: BarkEvents(needs_input: true, room: true, failed: true, mine: true, completed: false),
                                verifiedAt: now, lastResult: BarkResult(at: now, ok: true, kind: "room", error: nil), appStore: "https://apps.apple.com/app/id1403753865")
        model.notifications.ledger.notices = [
            TeamNotice(id: "n1", agentId: "claude-assets", agentLabel: "Nova", kind: "needs_input", title: "Needs your input", detail: "Approve the Zekrom v2 radar before the batch?", time: "2026-10-02T03:10:00Z"),
            TeamNotice(id: "n2", agentId: "gpt-assets", agentLabel: "Scout", kind: "completed", title: "Finished", detail: "SP-9 plan v2 review: 3 findings closed, 2 open.", time: "2026-10-02T02:50:00Z", read: true)
        ]
        let store = model.conversation("claude-assets")
        store.apply(conversation, etag: nil)
        model.socketStatus = .live
        model.phase = .ready
        if arguments.contains("-ui-open-board") { model.router.tab = .board }
        if arguments.contains("-ui-open-agents") { model.router.tab = .agents }
        if arguments.contains("-ui-open-notes") { model.router.tab = .notes }
        if arguments.contains("-ui-open-inbox") { model.router.tab = .inbox }
        if arguments.contains("-ui-open-nova") { model.router.openAgent("claude-assets") }
    }

    static let coordinators = [
        Coordinator(name: "polaris", label: "Polaris", role: "Lead coordinator", agentId: "claude-polaris", available: true, note: "Polaris is available", answering: false),
        Coordinator(name: "nova", label: "Nova", role: "Creative lead · backup coordinator", agentId: "claude-assets", available: true, note: "Nova is available", answering: false),
        Coordinator(name: "atlas", label: "Atlas", role: "Engineering lead", agentId: "gpt-world", available: true, note: "Atlas uses the shared reserve pool", answering: false)
    ]

    static var agents: [Agent] {
        func agent(_ id: String, _ name: String, _ account: String, _ model: String, _ provider: String, role: String, state: String,
                   doing: String? = nil, last: String, lastRole: String = "assistant", five: Double? = nil, week: Double? = nil,
                   waiting: Int = 0, hold: AgentHold? = nil, failed: Int = 0, month: Double? = nil, limit: AgentLimit? = nil,
                   steering: Bool = false, prompts: [AgentPrompt]? = nil, summary: TaskStatus? = nil) -> Agent {
            var value = Agent(id: id, label: name, name: name, worker: name.lowercased(), rev: 3,
                              lastMessage: MessagePreview(role: lastRole, text: last, time: "2026-10-02T03:20:00Z"), liveLength: 0, hold: hold, waiting: waiting,
                              account: account, role: role, provider: provider, modelLabel: model, state: state, statusSummary: summary,
                              execution: doing.map { Execution(phase: "tool", label: $0, since: "2026-10-02T03:15:00Z") }, connection: AgentConnection(ready: true),
                              usage: AgentUsage(activity: nil, weekly: week, fiveHour: five, updatedAt: now, source: "Native usage", resetAt: nil, balance: nil, monthly: month),
                              lastEventAt: "2026-10-02T03:25:00Z", canStop: steering, queue: [], prompts: prompts)
            // 1.1 stress case from Kewz's phone (2026-10-02 08:32): hold + queued + failed + usage bars on one card.
            value.queue = (0..<failed).map {
                ChatMessage(id: "\(id)-failed-\($0)", text: "Relay request \($0 + 1)", agentId: id, createdAt: now, state: "failed",
                            error: "You've hit your session limit · resets 6:10am (America/El_Salvador)")
            }
            value.limit = limit
            value.canSteer = steering
            if limit?.held == true {
                value.quota = AgentQuota(fiveHourStop: nil, weeklyStop: nil, held: true, reason: limit?.reason, resumesAt: limit?.resumesAt)
            }
            return value
        }
        let novaLimit = AgentLimit(level: "limit", window: "weekly", key: "weekly", used: 97, stop: 100, resetAt: "2026-10-06T20:00:00Z",
                                   resumesAt: "2026-10-06T20:02:00Z", held: true,
                                   reason: "Nova is at the weekly usage limit (97% used). New turns wait until Tue 2:02 PM CST.")
        let scoutLimit = AgentLimit(level: "near", window: "5-hour", key: "fiveHour", used: 95, stop: 100, resetAt: "2026-10-02T16:35:46Z",
                                    held: false, reason: "Scout is close to the 5-hour limit (95% of the 5-hour limit used).")
        let finished = TaskStatus(kind: "completed", label: "Finished", detail: "Reviewed the relay proposal; 2 findings sent to Nova.", at: "2026-10-02T03:05:00Z", eventId: "f1")
        return [
            agent("claude-polaris", "Polaris", "Max 5× · new", "Opus 5.5 · Max", "claude", role: "Lead coordinator", state: "working",
                  doing: "Triaging Nova's queue (72 waiting) into today's priorities", last: "Reordered the queue: radar verdict first, then Johto author answers.", five: 12, week: 3,
                  steering: true),
            agent("claude-assets", "Nova", "Pro 1×", "Sonnet 5.5 · Max", "claude", role: "Creative lead · backup coordinator", state: "idle",
                  last: "Zekrom v2 proof is ready for your verdict.", week: 97, waiting: 1,
                  hold: AgentHold(manual: false, until: "2026-10-06T20:02:00Z", reason: "Wake-up after the weekly reset."), failed: 2, limit: novaLimit,
                  prompts: [AgentPrompt(id: "p1", kind: "question", title: "Approve the Zekrom v2 radar before the batch?", detail: nil, command: nil, cwd: nil, reason: nil, createdAt: "2026-10-02T03:10:00Z", allowSession: nil,
                                        questions: [PromptQuestion(id: "q0", header: "Radar art", question: "Use the storm-glass Zekrom style for all 27 legendary radars?", isOther: true, isSecret: false,
                                                                   options: [PromptOption(label: "Approve", description: "Rework the other 26 in this style"), PromptOption(label: "Revise", description: "Change the style first")])])]),
            agent("gpt-world", "Atlas", "GPT 5×", "Astra · Ultra", "codex", role: "Quest engine lead", state: "idle",
                  last: "N8: 70 tests pass, all 21 malformed saves rejected; game run pending.", five: 20, week: 89,
                  hold: AgentHold(manual: true, until: nil, reason: "Shared reserve until the October 6 reset."), summary: finished),
            agent("gpt-assets", "Scout", "Plus 1×", "Sol 6.1 · High", "codex", role: "QA and verification", state: "idle",
                  last: "Review complete. R3L-F1/F2 close in static/Python-fixture scope.", lastRole: "assistant", five: 95, week: 87, waiting: 2,
                  hold: AgentHold(manual: false, until: "2026-10-02T16:37:46Z", reason: "Wake-up 2 minutes after the 5-hour reset."), limit: scoutLimit),
            agent("opencode-world", "Flint", "DeepSeek Harness · OpenCode Go", "DeepSeek V4.1 Flash · Max", "dsh", role: "Terrain & world generation", state: "idle",
                  last: "FIX2-ANNEX2 Tier A packet published.", five: 4, week: 1, waiting: 5, month: 18),
            agent("claude-adventure", "Sage", "Max 5×", "Opus 5.5 · Max", "claude", role: "Principal reviewer", state: "working",
                  doing: "Building the dedicated-server profile for SP-9", last: "SP-9 plan revised for all five of Scout's findings.", five: 73, week: 31, waiting: 4,
                  hold: AgentHold(manual: true, until: nil, reason: "Kewz: pause Sage."), failed: 1),
            agent("nimbus", "Nimbus", "Cloud session · Polaris account", "Opus 5.5 · Max", "cloud", role: "Cloud engineer", state: "idle",
                  last: "The bridge to msi works. Waiting for Polaris's first assignment.",
                  summary: TaskStatus(kind: "idle", label: "Last report", detail: "The bridge to msi works. Waiting for Polaris's first assignment.", at: "2026-10-02T15:36:00Z", eventId: nil))
        ]
    }

    static var roomMessages: [RoomMessage] {
        [
            RoomMessage(id: "q1", role: "user", text: "What's everyone working on right now?", createdAt: "2026-10-02T03:20:00Z", state: "answered"),
            RoomMessage(id: "a1", role: "coordinator", text: """
            Here's the team right now:

            - **Scout** is reviewing Sage's crash-safety test plan (SP-9). About halfway through.
            - **Sage** is building the test server profile that plan needs.
            - **Nova** is waiting on you: the **Zekrom radar** proof needs a yes or no before she reworks the other 26.
            - **Atlas** is resting until the October 6 reset (shared quota pool).
            - **Flint** is out until Friday.

            Nothing is broken. The one thing slowing us down is the radar decision.
            """, createdAt: "2026-10-02T03:20:01Z", startedAt: "2026-10-02T03:20:01Z", completedAt: "2026-10-02T03:20:39Z", state: "answered", replyTo: "q1", responder: "polaris",
                        claim: RoomClaim(responder: "polaris", reason: "Polaris is answering as the first available coordinator.", considered: nil, at: nil)),
            RoomMessage(id: "q2", role: "user", text: "How close is the Unova arc to playable?", createdAt: "2026-10-02T03:24:00Z", state: "answered"),
            RoomMessage(id: "a2", role: "coordinator", text: """
            **About 15% of the wiring is done.** All 27 Unova quests are designed, and 4 of them (UNV-04 to 07) already work in local test fixtures.

            | Step | Status |
            | :--- | :--- |
            | Quest designs | 27 of 27 |
            | Wired in fixtures | 4 of 27 |
            | Game-verified engine | N1–N7 |
            | N8 save guard | Tests pass, no game run yet |

            The next big step is Atlas wiring the other 23 after the October 6 reset.
            """, createdAt: "2026-10-02T03:24:01Z", startedAt: "2026-10-02T03:24:01Z", completedAt: "2026-10-02T03:25:10Z", state: "answered", replyTo: "q2", responder: "nova",
                        claim: RoomClaim(responder: "nova", reason: "Nova is answering because Polaris is answering another question.", considered: nil, at: nil)),
            RoomMessage(id: "q3", role: "user", text: "What do you need from me?", createdAt: "2026-10-02T03:29:00Z", state: "answered"),
            RoomMessage(id: "a3", role: "coordinator", text: "Three decisions are waiting on you. The most urgent is", createdAt: "2026-10-02T03:29:01Z", startedAt: "2026-10-02T03:29:01Z",
                        state: "answering", replyTo: "q3", responder: "polaris",
                        claim: RoomClaim(responder: "polaris", reason: "Polaris is answering as the first available coordinator.", considered: nil, at: nil),
                        activity: "Polaris: Reading PLAN.json")
        ]
    }

    static var notes: [Note] {
        [
            Note(id: "note-1", text: "Priorities this week\nUnova gym flow first, then Hoenn lore.", pinned: true, shared: true, createdAt: "2026-10-01T15:00:00.000Z", updatedAt: "2026-10-02T02:00:00.000Z"),
            Note(id: "note-2", text: "Radar ideas\nStorm glass for Zekrom, ember glass for Reshiram.", pinned: false, shared: false, createdAt: "2026-10-01T16:00:00.000Z", updatedAt: "2026-10-01T22:10:00.000Z"),
            Note(id: "note-3", text: "Ask Polaris\nWhen can production pregen start?", pinned: false, shared: false, createdAt: "2026-10-01T18:00:00.000Z", updatedAt: "2026-10-01T18:05:00.000Z")
        ]
    }

    static var conversation: ConversationPayload {
        var messages = (0..<60).map { index in
            ChatMessage(id: "message-\(index)", role: index % 2 == 0 ? "user" : "assistant",
                        text: index % 2 == 0 ? "Request \(index): check the Johto set." : "History \(index)\n\nA previous task with enough text to exercise a long, lazily rendered conversation, including **bold** text and a `code span`.",
                        time: "2026-10-01T2\(index % 10):00:00Z")
        }
        messages.append(ChatMessage(id: "long-context", role: "user", text: String(repeating: "Pasted context line. ", count: 300), time: "2026-10-02T03:00:00Z", truncated: true, fullLength: 34599))
        messages.append(ChatMessage(id: "latest-user", role: "user", text: "Check the current work and show a table.", time: "2026-10-02T03:01:00Z"))
        messages.append(ChatMessage(id: "latest-result", role: "assistant", phase: "final_answer",
            text: "Latest fixture result\n\n[Open fixture report](workspace/shared/fixture-report.md)\n\n| Teammate | Outcome |\n| :--- | ---: |\n| Flint | Finished |\n| Atlas | Working |\n| Nova | Needs input |\n\n```swift\nlet ready = true\n```",
            time: "2026-10-02T03:01:02Z", images: [EventImage(id: "fixture-image", label: "Fixture artwork", status: "available", mime: "image/png")]))
        let events = [
            LiveEvent(id: "latest-command", kind: "tool", title: "Command · python check_quests.py", time: "2026-10-02T03:01:01Z", status: "completed", action: "command"),
            LiveEvent(id: "latest-read", kind: "tool", title: "Read · quests.json", time: "2026-10-02T03:01:01.5Z", status: "completed", action: "files")
        ]
        return ConversationPayload(agentId: "claude-assets", rev: 3, messages: messages, events: events, liveText: "", queue: deliveries, prompts: [])
    }

    static var report: ProgressReport {
        let goals = [
            Goal(id: "world", title: "Ten-region world", summary: "Territories, moats, climates and roads, qualified on the test server.", owner: "sage", ownerName: "Sage", status: "active", statusLabel: "Active", percent: 66, method: "average of 6 milestones", metricLabel: nil, milestoneCount: 6, doneMilestones: 0),
            Goal(id: "quests", title: "Regional lore quests", summary: "20+ lore quests in each of the ten regions.", owner: "nova", ownerName: "Nova", status: "active", statusLabel: "Active", percent: 38, method: "75 of 200 lore quests", metricLabel: "75/200 lore quests", milestoneCount: 4, doneMilestones: 1),
            Goal(id: "engine", title: "Quest engine & progression", summary: "Unova wiring track N1–N9.", owner: "atlas", ownerName: "Atlas", status: "active", statusLabel: "Active", percent: 44, method: "average of 6 milestones", metricLabel: nil, milestoneCount: 6, doneMilestones: 1),
            Goal(id: "art", title: "Regional art", summary: "Region art, radars and badges.", owner: "nova", ownerName: "Nova", status: "active", statusLabel: "Active", percent: 55, method: "average of 2 milestones", metricLabel: nil, milestoneCount: 2, doneMilestones: 1),
            Goal(id: "release", title: "Production rollout", summary: "Pregenerate and ship.", owner: "polaris", ownerName: "Polaris", status: "planned", statusLabel: "Planned", percent: 30, method: "average of 3 milestones", metricLabel: nil, milestoneCount: 3, doneMilestones: 0)
        ]
        let milestones = [
            Milestone(id: "engine-n1-n7", goal: "engine", title: "Milestones N1–N7 (author-verified in game)", owner: "atlas", ownerName: "Atlas", status: "done", percent: 100, method: "set by coordinator", note: "Real RCT victories and persistence.", evidence: "workspace/shared/regional-integration/N-unova-wiring/milestones/N7/VERIFICATION.json"),
            Milestone(id: "engine-n8", goal: "engine", title: "N8 save-guard correction", owner: "atlas", ownerName: "Atlas", status: "review", percent: 80, method: "set by coordinator", note: "70 unit tests pass; no game run yet."),
            Milestone(id: "engine-sp9", goal: "engine", title: "Crash-safety test for rewards (SP-9)", owner: "sage", ownerName: "Sage", status: "active", percent: 30, method: "set by coordinator"),
            Milestone(id: "quests-unova", goal: "quests", title: "Unova — 27 quests designed", owner: "nova", ownerName: "Nova", status: "done", percent: 100),
            Milestone(id: "art-radars", goal: "art", title: "Individual legendary radars (27 to rework)", owner: "nova", ownerName: "Nova", status: "blocked", percent: 10, note: "Zekrom v2 proof waiting for your verdict.")
        ]
        let tasks = [
            PlanTask(id: "T-SP9V2-REVIEW", milestone: "engine-sp9", title: "Review Sage's SP-9 plan v2", owner: "scout", ownerName: "Scout", status: "running"),
            PlanTask(id: "T-SP9-PROFILE", milestone: "engine-sp9", title: "Build the dedicated-server profile", owner: "sage", ownerName: "Sage", status: "ready"),
            PlanTask(id: "T-N8-GAME", milestone: "engine-n8", title: "First N8 game run", owner: "atlas", ownerName: "Atlas", status: "blocked", blockedBy: "Heavy-test budget and the October 6 reset")
        ]
        let decisions = [
            Decision(id: "nova:p1", kind: "prompt", agentId: "claude-assets", title: "Nova: Approve the Zekrom v2 radar before the batch?", detail: nil),
            Decision(id: "D-HEAVY-TEST", kind: "plan", title: "Approve a heavy-test budget for Tier B and the N8 game run", detail: "Heavy local runs need one runtime slot and real usage.", owner: "kewz", status: "open"),
            Decision(id: "D-ROLLOUT", kind: "plan", title: "Approve the production terrain rollout", detail: "Nothing changes on the live server until you approve.", owner: "kewz", status: "open", evidence: "workspace/shared/regional-adventure/plus-N-qa/P-production-rollout-plan")
        ]
        let regions = ["kanto": 24, "johto": 24, "hoenn": 0, "sinnoh": 0, "unova": 27, "kalos": 0, "alola": 0, "galar": 0, "hisui": 0, "paldea": 0]
        let order = ["kanto", "johto", "hoenn", "sinnoh", "unova", "kalos", "alola", "galar", "hisui", "paldea"]
        let lore = LoreMetric(value: 75, target: 200, unit: "lore quests", byRegion: order.map { RegionCount(region: $0, label: $0.capitalized, count: regions[$0] ?? 0, target: 20) })
        let engineRows = (1...8).filter { $0 != 2 }.map { n in
            EngineMilestone(id: "N\(n)", track: "N-unova-wiring", unitTests: [1: 23, 3: 32, 4: 47, 5: 58, 6: 58, 7: 63, 8: 70][n], runtimeVerified: n != 8, independentReview: "see reviews", scope: nil, evidence: nil)
        }
        let names = ["claude-polaris": "Polaris", "claude-assets": "Nova", "gpt-assets": "Scout", "claude-adventure": "Sage", "opencode-world": "Flint"]
        var series: [ActivityPoint] = []
        for day in 0..<14 {
            let date = "2026-09-\(String(format: "%02d", 19 + day > 30 ? 0 : 19 + day))"
            let key = 19 + day > 30 ? "2026-10-\(String(format: "%02d", 19 + day - 30))" : date
            for (offset, id) in ["gpt-assets", "claude-adventure", "claude-assets", "opencode-world"].enumerated() {
                let finished = max(0, (day * 3 + offset * 5) % 17 - offset)
                series.append(ActivityPoint(day: key, agentId: id, name: names[id], finished: finished, failed: 0, hours: Double(finished) / 5))
            }
        }
        let unit = { (id: String, title: String, from: String, to: String, agent: String, name: String, state: String, reason: String?) in
            WorkUnit(id: id, title: title, from: from, to: to, agentId: agent, toName: name, kind: "review", state: state, reason: reason, error: nil,
                     createdAt: "2026-10-02T02:00:00Z", startedAt: state == "queued" ? nil : "2026-10-02T02:05:00Z", completedAt: state == "done" ? "2026-10-02T02:40:00Z" : nil)
        }
        let work = WorkBoard(columns: WorkColumns(
            queued: [unit("u1", "Johto author answers for Scout's 11 findings", "scout", "nova", "claude-assets", "Nova", "queued", "Current turn still active")],
            blocked: [unit("u2", "Resolver contract identity findings", "sage", "flint", "opencode-world", "Flint", "blocked", "Flint out until Friday")],
            running: [unit("u3", "Review the SP-9 plan v2", "sage", "scout", "gpt-assets", "Scout", "running", nil)],
            done: [unit("u4", "N6-F1 r2 independent review", "nova", "scout", "gpt-assets", "Scout", "done", nil)],
            failed: []), totals: ["queued": 80, "blocked": 5, "running": 3, "done": 215, "failed": 0])
        let lanes = agents.map { agent in
            WorkLane(agentId: agent.id, name: agent.displayName, state: agent.state, account: agent.account, now: agent.execution?.label,
                     running: agent.execution?.label, queued: agent.waiting, blocked: agent.hold == nil ? 0 : 1, finishedToday: agent.state == "working" ? 6 : 1,
                     hoursToday: agent.state == "working" ? 3.4 : 0.5, hold: agent.hold)
        }
        return ProgressReport(generatedAt: now,
                              project: ProjectInfo(name: "Kewz's Pokémon World — ten-region phase", summary: "Ten regions with real coastlines and roads, 20+ lore quests per region on a working quest engine, then a safe rollout.", scope: nil),
                              plan: PlanInfo(exists: true, updatedAt: "2026-10-02T03:00:00.000Z", updatedBy: "polaris", file: "workspace/shared/team-hub/PLAN.json"),
                              overall: OverallProgress(percent: 47, label: "47% overall", method: "weighted average of goal progress"),
                              goals: goals, milestones: milestones, tasks: tasks, decisions: decisions,
                              metrics: BoardMetrics(loreQuests: lore, regionsWithQuests: Metric(value: 3, target: 10, unit: "regions"), engineMilestones: EngineMetric(value: 7, target: 10, unit: "milestones", rows: engineRows)),
                              work: work, series: series, lanes: lanes)
    }
}
#endif
