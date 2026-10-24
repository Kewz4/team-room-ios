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
        if arguments.contains("-ui-open-rigel") { model.router.openAgent("claude-rigel") }
        if arguments.contains("-ui-open-lyra") { model.router.openAgent("claude-lyra") }
        model.updateCheckedAt = Date()
        if arguments.contains("-ui-update-banner") {
            model.update = AppUpdateInfo(build: 16, version: "1.3.1", notes: "A faster agents list and a fix for the spend chart.",
                                         installUrl: "itms-services://?action=download-manifest&url=https%3A%2F%2Fexample.invalid%2Fteamroom.plist")
        }
    }

    /// 1.2: the roster Kewz set on 2026-10-04 (Vega and Orion joined; Nimbus retired).
    static let coordinators = [
        Coordinator(name: "polaris", label: "Polaris", role: "Lead coordinator", agentId: "claude-polaris", available: true, note: "Polaris is available", answering: false),
        Coordinator(name: "sage", label: "Sage", role: "Principal reviewer · coordinator", agentId: "claude-adventure", available: true, note: "Sage is available", answering: false),
        Coordinator(name: "vega", label: "Vega", role: "Engineering · coordinator", agentId: "claude-vega", available: true, note: "Vega is available", answering: false),
        Coordinator(name: "orion", label: "Orion", role: "Building & world engineering · coordinator", agentId: "claude-orion", available: true, note: "Orion is available", answering: false),
        Coordinator(name: "atlas", label: "Atlas", role: "Engineering lead · coordinator", agentId: "gpt-world", available: true, note: "Atlas uses the shared reserve pool", answering: false)
    ]

    static var agents: [Agent] {
        func agent(_ id: String, _ name: String, _ account: String, _ model: String, _ provider: String, role: String, state: String,
                   doing: String? = nil, last: String, lastRole: String = "assistant", five: Double? = nil, week: Double? = nil,
                   waiting: Int = 0, hold: AgentHold? = nil, failed: Int = 0, month: Double? = nil, limit: AgentLimit? = nil,
                   steering: Bool = false, prompts: [AgentPrompt]? = nil, summary: TaskStatus? = nil, budget: AgentBudget? = nil) -> Agent {
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
            value.usage?.budget = budget
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
            // 1.2: Vega and Orion share the Polaris and Sage accounts, so each shows its account's usage and stops with it.
            agent("claude-vega", "Vega", "Max 5× · Polaris account", "Opus 5.5 · Max", "claude", role: "Engineering · coordinator", state: "working",
                  doing: "K-P1d: Sage's four Kanto findings", last: "Intake done: Nimbus's handoff, the Kanto kit and the board.", five: 12, week: 3),
            agent("claude-orion", "Orion", "Max 5× · Sage account", "Opus 5.5 · Max", "claude", role: "Building & world engineering · coordinator", state: "idle",
                  last: "Intake done. Light duty until the October 8 reset.", five: 73, week: 31,
                  summary: TaskStatus(kind: "idle", label: "Last report", detail: "Ready for the Battle Tower fix.", at: "2026-10-02T03:10:00Z", eventId: nil)),
            // 1.3: the API-credit workers, with the money they have spent by 2026-10-27 (cycle started 10-23).
            agent("claude-rigel", "Rigel", "Max 20× · API credit", "Sonnet 5.5 · High", "claude", role: "API-credit worker", state: "working",
                  doing: "Task 0003: the DeepSeek agent and its money counter", last: "Room integration is in: both workers show in the team list.",
                  budget: budget(credit: 200, renews: "2026-11-14T00:00:00.000Z", cap: 9.25, today: 1.20,
                                 before: [6.90, 8.85, 7.60, 7.85], daysLeft: 18)),
            agent("claude-lyra", "Lyra", "Max 5× · API credit", "Sonnet 5.5 · High", "claude", role: "API-credit worker", state: "idle",
                  last: "The iOS app shows spend and update notices; the build is green.",
                  budget: budget(credit: 100, renews: "2026-11-19T00:00:00.000Z", cap: 3.75, today: 0.85,
                                 before: [2.60, 3.45, 3.10, 3.65], daysLeft: 23))
        ]
    }

    /// 14 days ending 2026-10-27: zero before the cycle began, then `before` and today's spend.
    static func budget(credit: Double, renews: String, cap: Double, today: Double, before: [Double], daysLeft: Double) -> AgentBudget {
        let spentBefore = before.reduce(0, +)
        let amounts = [Double](repeating: 0, count: 13 - before.count) + before + [today]
        let history = zip(14...27, amounts).map { AgentBudget.Day(day: String(format: "2026-10-%02d", $0), spent: $1) }
        return AgentBudget(kind: "api-credit", currency: "USD", model: "claude-sonnet-5-5", effort: "high", pacing: "carry",
                           today: AgentBudget.Today(day: "2026-10-27", spent: today, cap: cap, left: cap - today),
                           cycle: AgentBudget.Cycle(start: "2026-10-23T00:00:00.000Z", renewsAt: renews, credit: credit,
                                                    spent: spentBefore + today, left: credit - spentBefore - today, daysLeft: daysLeft),
                           history: history, lastRunAt: "2026-10-27T15:20:00.000Z", observedAt: "2026-10-27T15:30:00.000Z",
                           source: "Agent SDK run costs (local ledger)")
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
            - **Vega** is fixing the four Kanto quest findings from Sage's review.
            - **Orion** is on light duty until the October 8 reset.
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
            """, createdAt: "2026-10-02T03:24:01Z", startedAt: "2026-10-02T03:24:01Z", completedAt: "2026-10-02T03:25:10Z", state: "answered", replyTo: "q2", responder: "vega",
                        claim: RoomClaim(responder: "vega", reason: "Vega is answering because Polaris is answering another question.", considered: nil, at: nil)),
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
            Note(id: "note-3", text: "Ask Polaris\nWhen can production pregen start?", pinned: false, shared: false, createdAt: "2026-10-01T18:00:00.000Z", updatedAt: "2026-10-01T18:05:00.000Z"),
            // 1.2: a long note, so the UI test proves its last line can be reached with and without the keyboard.
            Note(id: "note-long", text: longNote, pinned: false, shared: false, createdAt: "2026-10-01T12:00:00.000Z", updatedAt: "2026-10-01T12:30:00.000Z")
        ]
    }

    static var longNote: String {
        (["Hoenn trip ideas"] + (1...90).map { "Idea \($0): a stop on the route and what to check there." } + ["Last line of the long note"])
            .joined(separator: "\n")
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
            Goal(id: "world", title: "Ten-region world", summary: "Region territories, ocean moats, climates and region-styled roads, qualified on the Godlike test server before any production change.", owner: "sage", ownerName: "Sage", status: "active", statusLabel: "Active", percent: 38, method: "average of 6 milestones", metricLabel: nil, milestoneCount: 6, doneMilestones: 0, track: "ten-region", weight: 15),
            Goal(id: "quests", title: "Quests & story", summary: "20+ lore quests per region, a required main story with optional side quests in every region, really hard side quests and Easter eggs, and NPCs who trade for or buy Pokémon.", owner: "nova", ownerName: "Nova", status: "active", statusLabel: "Active", percent: 57, method: "average of 12 milestones", metricLabel: nil, milestoneCount: 12, doneMilestones: 0, track: "ten-region", weight: 15),
            Goal(id: "engine", title: "Quest engine & progression", summary: "The Unova wiring track: quest identity, persistence, rewards, RCT progression and save safety, proven milestone by milestone (N1–N8, then N9+).", owner: "atlas", ownerName: "Atlas", status: "active", statusLabel: "Active", percent: 50, method: "average of 6 milestones", metricLabel: nil, milestoneCount: 6, doneMilestones: 0, track: "ten-region", weight: 10),
            Goal(id: "art", title: "Regional art & identity", summary: "Recognisable art for all ten regions, the legendary radars, and a region welcome: a title with artwork and a fly-over of the region when you arrive.", owner: "nova", ownerName: "Nova", status: "active", statusLabel: "Active", percent: 39, method: "average of 3 milestones", metricLabel: nil, milestoneCount: 3, doneMilestones: 0, track: "ten-region", weight: 5),
            Goal(id: "release", title: "Production rollout", summary: "A safe production rollout of the ten-region world, plus the client updater as a mod for Android and Linux players.", owner: "polaris", ownerName: "Polaris", status: "planned", statusLabel: "Planned", percent: 20, method: "average of 4 milestones", metricLabel: nil, milestoneCount: 4, doneMilestones: 0, track: "ten-region", weight: 10),
            Goal(id: "economy", title: "Economy rework", summary: "Rework the whole economy: shops, every way to make money, every sell and buy price. Farms stay possible but are hard, risky and high-reward; the dynamic sell prices feel polished, sensible and not too punishing.", owner: "polaris", ownerName: "Polaris", status: "active", statusLabel: "Active", percent: 5, method: "average of 6 milestones", metricLabel: nil, milestoneCount: 6, doneMilestones: 0, track: "pack", weight: 15),
            Goal(id: "mods", title: "Mod additions & updates", summary: "Kewz's list (permission to fork and use every one): the two raid-den mods, the Eeveelutions and Animated Mon updates, Oracle Index, a conveyor-belt mod and tree felling. Each: exact Fabric 1.21.1 version, compatibility check, test-server boot, client release.", owner: "polaris", ownerName: "Polaris", status: "active", statusLabel: "Active", percent: 0, method: "average of 3 milestones", metricLabel: nil, milestoneCount: 3, doneMilestones: 0, track: "pack", weight: 10),
            Goal(id: "living", title: "Living world", summary: "Make the world feel alive: AI players who roam, battle, trade and shop; trainers that spawn where they belong; a rival; NPCs who trade or buy Pokémon; Clavis everywhere; Oritech tied into Cobblemon.", owner: "vega", ownerName: "Vega", status: "active", statusLabel: "Active", percent: 0, method: "average of 6 milestones", metricLabel: nil, milestoneCount: 6, doneMilestones: 0, track: "pack", weight: 10),
            Goal(id: "polish", title: "Pack polish & fixes", summary: "The fixes and clean-ups from Kewz's note: EMI tidy-up and item tags, UI overlaps, the smartphone Info app, the Battle Tower hologram, z-fighting, winter and loot tables.", owner: "scout", ownerName: "Scout", status: "active", statusLabel: "Active", percent: 0, method: "average of 4 milestones", metricLabel: nil, milestoneCount: 4, doneMilestones: 0, track: "pack", weight: 10)
        ]
        let milestones = [
            Milestone(id: "world-territories", goal: "world", title: "Region territories & biome palettes", owner: "flint", ownerName: "Flint", status: "active", percent: 45),
            Milestone(id: "world-moats", goal: "world", title: "Ocean moats between territories", owner: "sage", ownerName: "Sage", status: "active", percent: 55),
            Milestone(id: "world-roads", goal: "world", title: "Region-styled roads", owner: "sage", ownerName: "Sage", status: "active", percent: 50),
            Milestone(id: "world-climate", goal: "world", title: "Region climates, spawns & roadside builds", owner: "sage", ownerName: "Sage", status: "active", percent: 40),
            Milestone(id: "world-client-view", goal: "world", title: "Client terrain view (Voxy water)", owner: "sage", ownerName: "Sage", status: "active", percent: 30),
            Milestone(id: "world-tierb", goal: "world", title: "Qualify the current terrain on the test server (every territory)", owner: "sage", ownerName: "Sage", status: "blocked", percent: 10),
            Milestone(id: "quests-unova", goal: "quests", title: "Unova — 27 lore quests (Black/White)", owner: "nova", ownerName: "Nova", status: "active", percent: 70),
            Milestone(id: "quests-kanto", goal: "quests", title: "Kanto — 24 quests designed & QA'd (FireRed/LeafGreen)", owner: "nova", ownerName: "Nova", status: "active", percent: 60),
            Milestone(id: "quests-johto", goal: "quests", title: "Johto — 24 quests designed & QA'd", owner: "nova", ownerName: "Nova", status: "active", percent: 70),
            Milestone(id: "quests-remaining", goal: "quests", title: "Hoenn — lore set (20+ quests)", owner: "nova", ownerName: "Nova", status: "active", percent: 50),
            Milestone(id: "engine-n1-n7", goal: "engine", title: "Milestones N1–N7 (author-verified in game)", owner: "atlas", ownerName: "Atlas", status: "review", percent: 80),
            Milestone(id: "engine-n8", goal: "engine", title: "N8 save-guard correction", owner: "atlas", ownerName: "Atlas", status: "active", percent: 50),
            Milestone(id: "engine-n6f1", goal: "engine", title: "Fix cold-login RCT progress loss (N6-F1)", owner: "sage", ownerName: "Sage", status: "active", percent: 55),
            Milestone(id: "engine-sp9", goal: "engine", title: "Crash-safety test for rewards (SP-9)", owner: "sage", ownerName: "Sage", status: "active", percent: 40),
            Milestone(id: "engine-unova-wiring", goal: "engine", title: "Wire the Unova quest arc into the game", owner: "atlas", ownerName: "Atlas", status: "active", percent: 10),
            Milestone(id: "engine-n9", goal: "engine", title: "N9 engine follow-ups (Sage's SP-3 to SP-6, restore, terrain keys, Johto adapters)", owner: "atlas", ownerName: "Atlas", status: "active", percent: 62),
            Milestone(id: "art-region-sets", goal: "art", title: "Source art for all ten regions", owner: "nova", ownerName: "Nova", status: "review", percent: 45),
            Milestone(id: "art-radars", goal: "art", title: "Individual legendary radars (27 to rework)", owner: "nova", ownerName: "Nova", status: "active", percent: 73),
            Milestone(id: "release-plan", goal: "release", title: "Rollout & rollback plan", owner: "scout", ownerName: "Scout", status: "active", percent: 30),
            Milestone(id: "release-pregen", goal: "release", title: "Production pregeneration (RoadWeaver plans first)", owner: "polaris", ownerName: "Polaris", status: "planned", percent: 0),
            Milestone(id: "release-ship", goal: "release", title: "Server and client release", owner: "polaris", ownerName: "Polaris", status: "planned", percent: 0),
            Milestone(id: "quests-sinnoh", goal: "quests", title: "Sinnoh — lore set (20+ quests)", owner: "nova", ownerName: "Nova", status: "active", percent: 70),
            Milestone(id: "quests-kalos", goal: "quests", title: "Kalos — lore set (20+ quests)", owner: "nova", ownerName: "Nova", status: "active", percent: 70),
            Milestone(id: "quests-alola", goal: "quests", title: "Alola — lore set (20+ quests)", owner: "nova", ownerName: "Nova", status: "active", percent: 70),
            Milestone(id: "quests-galar", goal: "quests", title: "Galar — lore set (20+ quests)", owner: "nova", ownerName: "Nova", status: "active", percent: 70),
            Milestone(id: "quests-hisui", goal: "quests", title: "Hisui — lore set (20+ quests)", owner: "nova", ownerName: "Nova", status: "active", percent: 70),
            Milestone(id: "quests-paldea", goal: "quests", title: "Paldea — lore set (20+ quests)", owner: "nova", ownerName: "Nova", status: "active", percent: 70),
            Milestone(id: "econ-audit", goal: "economy", title: "Economy map: every way coins come in and go out", owner: "polaris", ownerName: "Polaris", status: "active", percent: 0),
            Milestone(id: "econ-dynamic", goal: "economy", title: "Dynamic sell prices: live per player, then polished", owner: "sage", ownerName: "Sage", status: "active", percent: 30),
            Milestone(id: "econ-prices", goal: "economy", title: "Rebalance every sell and buy price; make more things sellable", owner: "polaris", ownerName: "Polaris", status: "planned", percent: 0),
            Milestone(id: "econ-jobs", goal: "economy", title: "Jobs+ jobs system, balanced for Cobblemon and CobbleDollars", owner: "vega", ownerName: "Vega", status: "planned", percent: 0),
            Milestone(id: "econ-minigames", goal: "economy", title: "Cobblemon MiniGames, joined to the Team Rocket casino", owner: "vega", ownerName: "Vega", status: "planned", percent: 0),
            Milestone(id: "econ-cobblebase", goal: "economy", title: "CobbleBase: harder to farm and more interactive", owner: "orion", ownerName: "Orion", status: "planned", percent: 0),
            Milestone(id: "mods-dens", goal: "mods", title: "Raid dens: Dens More Faithful and Enhanced Dens (CurseForge)", owner: "flint", ownerName: "Flint", status: "planned", percent: 0),
            Milestone(id: "mods-updates", goal: "mods", title: "Updates: Kazeran's Eeveelutions and Animated Mon", owner: "flint", ownerName: "Flint", status: "planned", percent: 0),
            Milestone(id: "mods-new", goal: "mods", title: "New mods: Oracle Index, a conveyor-belt mod, tree felling", owner: "flint", ownerName: "Flint", status: "planned", percent: 0),
            Milestone(id: "living-ai-players", goal: "living", title: "AI players who roam, battle, trade and shop", owner: "vega", ownerName: "Vega", status: "planned", percent: 0),
            Milestone(id: "living-trainer-biomes", goal: "living", title: "Trainers spawn by biome: hikers in mountains, cave trainers in caves", owner: "orion", ownerName: "Orion", status: "planned", percent: 0),
            Milestone(id: "living-rival", goal: "living", title: "A rival? (proposal for Kewz)", owner: "nova", ownerName: "Nova", status: "planned", percent: 0),
            Milestone(id: "living-trade-npcs", goal: "living", title: "NPCs and quests that trade for or buy Pokémon", owner: "nova", ownerName: "Nova", status: "planned", percent: 0),
            Milestone(id: "living-clavis", goal: "living", title: "Clavis: in more places, with new mini-games and screens", owner: "atlas", ownerName: "Atlas", status: "planned", percent: 0),
            Milestone(id: "living-oritech", goal: "living", title: "Oritech and Cobblemon working together (ideas first)", owner: "vega", ownerName: "Vega", status: "planned", percent: 0),
            Milestone(id: "quests-main-side", goal: "quests", title: "Main story vs optional side quests in every region", owner: "nova", ownerName: "Nova", status: "active", percent: 10),
            Milestone(id: "quests-side-extra", goal: "quests", title: "Really hard side quests, Easter eggs and more quests", owner: "nova", ownerName: "Nova", status: "planned", percent: 0),
            Milestone(id: "art-region-welcome", goal: "art", title: "Region welcome: a 'Welcome to Galar' title with artwork, and a fly-over", owner: "nova", ownerName: "Nova", status: "planned", percent: 0),
            Milestone(id: "release-updater-mod", goal: "release", title: "Updater as a mod for Android and Linux", owner: "polaris", ownerName: "Polaris", status: "review", percent: 50),
            Milestone(id: "polish-emi", goal: "polish", title: "EMI tidy-up: hide the biome tiles, group items, fix item tags", owner: "scout", ownerName: "Scout", status: "planned", percent: 0),
            Milestone(id: "polish-ui", goal: "polish", title: "UI fixes: netherite chest overlap, smartphone Info app, Battle Tower hologram", owner: "scout", ownerName: "Scout", status: "planned", percent: 0),
            Milestone(id: "polish-render", goal: "polish", title: "Fix z-fighting, with and without shaders", owner: "scout", ownerName: "Scout", status: "planned", percent: 0),
            Milestone(id: "polish-balance", goal: "polish", title: "Shorter or milder winter; loot tables balanced where needed", owner: "orion", ownerName: "Orion", status: "planned", percent: 0)
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
        let regions = ["kanto": 25, "johto": 24, "hoenn": 26, "sinnoh": 24, "unova": 27, "kalos": 25, "alola": 25, "galar": 24, "hisui": 24, "paldea": 24]
        let order = ["kanto", "johto", "hoenn", "sinnoh", "unova", "kalos", "alola", "galar", "hisui", "paldea"]
        let lore = LoreMetric(value: 248, target: 200, unit: "lore quests", byRegion: order.map { RegionCount(region: $0, label: $0.capitalized, count: regions[$0] ?? 0, target: 20) })
        let engineRows = (1...8).filter { $0 != 2 }.map { n in
            EngineMilestone(id: "N\(n)", track: "N-unova-wiring", unitTests: [1: 23, 3: 32, 4: 47, 5: 58, 6: 58, 7: 63, 8: 70][n], runtimeVerified: n != 8, independentReview: "see reviews", scope: nil, evidence: nil)
        }
        let names = ["claude-polaris": "Polaris", "claude-assets": "Nova", "gpt-assets": "Scout", "claude-adventure": "Sage", "opencode-world": "Flint",
                     "claude-vega": "Vega", "claude-orion": "Orion"]
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
                              project: ProjectInfo(name: "Kewz's Pokémon World — ten regions and a living, balanced pack", summary: "Two tracks on one board: the ten-region phase (territories, 20+ lore quests per region on a working quest engine, regional art, a safe rollout) and the pack (economy, mods, a living world, polish).", scope: nil),
                              plan: PlanInfo(exists: true, updatedAt: "2026-10-02T03:00:00.000Z", updatedBy: "polaris", file: "workspace/shared/team-hub/PLAN.json"),
                              overall: OverallProgress(percent: 24, label: "24% overall", method: "weighted average of goal progress"),
                              goals: goals, milestones: milestones, tasks: tasks, decisions: decisions,
                              metrics: BoardMetrics(loreQuests: lore, regionsWithQuests: Metric(value: 10, target: 10, unit: "regions"), engineMilestones: EngineMetric(value: 7, target: 10, unit: "milestones", rows: engineRows)),
                              work: work, series: series, lanes: lanes)
    }
}
#endif
