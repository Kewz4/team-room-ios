import XCTest
@testable import TeamRoom

final class TeamRoomTests: XCTestCase {
    func testSharedFileLinksAndExternalLinksHaveDistinctRoutes() {
        XCTAssertEqual(LinkRouting.resolve(URL(string: "workspace/shared/report.md")!), .artifact("workspace/shared/report.md"))
        XCTAssertEqual(LinkRouting.resolve(URL(string: "C:/Users/Kenneth%20Rodas/report.md:12")!), .artifact("C:/Users/Kenneth Rodas/report.md"))
        XCTAssertEqual(LinkRouting.resolve(URL(string: "SOURCES.md")!, relativeTo: "workspace/shared/unova/QUESTS.md"), .artifact("workspace/shared/unova/SOURCES.md"))
        let web = URL(string: "https://example.com/reference")!
        XCTAssertEqual(LinkRouting.resolve(web), .web(web))
        XCTAssertEqual(LinkRouting.resolve(URL(string: "javascript:alert(1)")!), .unsupported)
    }

    func testWindowsMarkdownTargetsWithSpacesAreEncoded() {
        let prepared = LinkRouting.prepareMarkdown("[report](<C:/Users/Kenneth Rodas/Report.md>)")
        XCTAssertTrue(prepared.contains("Kenneth%20Rodas"))
        XCTAssertFalse(prepared.contains("<C:"))
    }

    func testMarkdownTablePreservesColumnsInlineCodeEscapedPipesAndRaggedRows() {
        let text = "Intro\n\n| Name | Value |\n| :--- | ---: |\n| **A** | `x|y` |\n| B \\| C | 2 |\n| short |\n\nAfter"
        let blocks = MarkdownBlocks.parse(text)
        XCTAssertEqual(blocks.count, 3)
        guard case .table(let table) = blocks[1].kind else { return XCTFail("Expected table") }
        XCTAssertEqual(table.headers, ["Name", "Value"])
        XCTAssertEqual(table.rows, [["**A**", "`x|y`"], ["B | C", "2"], ["short", ""]])
        XCTAssertEqual(table.alignments, [.leading, .trailing])
    }

    func testFencesAndPipeProseAreNotTables() {
        let blocks = MarkdownBlocks.parse("```text\n| A | B |\n| --- | --- |\n```\n\nA | B\njust prose")
        XCTAssertEqual(blocks.count, 2)
        guard case .code = blocks[0].kind, case .paragraph = blocks[1].kind else { return XCTFail("Incorrect table detection") }
    }

    func testRenderedMarkdownPrebuildsInlineTextAndTableCellsAndIsCached() {
        let text = "# Title\n\nSome **bold** text.\n\n| A | B |\n| --- | --- |\n| `1` | two |"
        let rendered = MarkdownRenderer.shared.render(text)
        XCTAssertEqual(rendered.blocks.count, 3)
        guard case .table = rendered.blocks[2].kind else { return XCTFail("Expected table") }
        XCTAssertEqual(rendered.blocks[2].cells.count, 2)
        XCTAssertEqual(String(rendered.blocks[1].attributed.characters), "Some bold text.")
        XCTAssertEqual(MarkdownRenderer.shared.render(text).blocks.count, 3)
    }

    func testNoticeLedgerBaselinesOnceDeduplicatesAndIgnoresRelayCompletions() throws {
        func agent(_ event: String, run: String?, kind: String = "completed") -> Agent {
            Agent(id: "a", label: "Astra", state: "idle", statusSummary: TaskStatus(kind: kind, label: "Finished", eventId: event, runId: run))
        }
        let mine = "6f1c2a4e-1111-4222-8333-944455556666"
        var ledger = NoticeLedger()
        XCTAssertTrue(ledger.consume([agent("old", run: mine)]).isEmpty)
        XCTAssertEqual(ledger.consume([agent("new", run: mine)]).count, 1)
        XCTAssertTrue(ledger.consume([agent("new", run: mine)]).isEmpty)
        XCTAssertTrue(ledger.consume([agent("relay-done", run: "p-scout-sage-review-20261002")]).isEmpty, "relay continuations are not news")
        XCTAssertEqual(ledger.consume([agent("relay-failed", run: "p-scout-x-20261002", kind: "failed")]).count, 1, "failures always are")
        let data = try JSONEncoder().encode(ledger)
        var restored = try JSONDecoder().decode(NoticeLedger.self, from: data)
        XCTAssertTrue(restored.consume([agent("relay-failed", run: "p-scout-x-20261002", kind: "failed")]).isEmpty)
        XCTAssertEqual(restored.notices.count, 2)
    }

    func testWorkingStateCannotBeOverriddenByStaleFinishedSummary() {
        let a = Agent(id: "a", label: "A", state: "working", statusSummary: TaskStatus(kind: "completed", label: "Finished", eventId: "old"))
        XCTAssertEqual(a.taskStatus.kind, "working")
    }

    // MARK: - Live updates

    func testStreamDeltasAppendWithUTF16BasesAndResyncWhenOutOfStep() throws {
        func frame(_ json: String) throws -> LiveFrame { try JSONDecoder().decode(LiveFrame.self, from: Data(json.utf8)) }
        var text = try XCTUnwrap(StreamDelta.apply(try frame(#"{"type":"stream","agentId":"a","reset":true,"base":0,"text":"Hi 👋"}"#), to: "stale"))
        XCTAssertEqual(text, "Hi 👋")
        // JavaScript length of "Hi 👋" is 5 UTF-16 units, not 4 characters.
        text = try XCTUnwrap(StreamDelta.apply(try frame(#"{"type":"stream","agentId":"a","base":5,"append":" there"}"#), to: text))
        XCTAssertEqual(text, "Hi 👋 there")
        XCTAssertNil(StreamDelta.apply(try frame(#"{"type":"stream","agentId":"a","base":3,"append":"x"}"#), to: text))
    }

    /// 1.1: limit awareness, OpenCode Go's monthly window and steering decode from /api/team summaries.
    func testLimitMonthlyAndSteeringFieldsDecode() throws {
        let json = #"{"id":"opencode-world","label":"Flint","state":"working","canStop":true,"canSteer":true,"usage":{"fiveHour":12,"fiveHourResetAt":"2026-10-02T19:47:04.617Z","weekly":40,"resetAt":"2026-10-05T00:00:00.000Z","monthly":91,"monthlyResetAt":"2026-11-02T14:20:11.000Z","source":"Native OpenCode Go usage"},"limit":{"level":"near","window":"monthly","key":"monthly","used":91,"stop":100,"held":false,"reason":"Flint is close to the monthly limit (91% of the monthly limit used)."}}"#
        let agent = try JSONDecoder().decode(Agent.self, from: Data(json.utf8))
        XCTAssertEqual(agent.usage?.monthly, 91)
        XCTAssertEqual(agent.usage?.fiveHourResetAt, "2026-10-02T19:47:04.617Z")
        XCTAssertEqual(agent.limit?.level, "near")
        XCTAssertTrue(agent.limit?.isNear == true)
        XCTAssertTrue(agent.steerable)
        XCTAssertTrue(UsageBars.shows(agent.usage))
        // An idle teammate, or one whose turn the Team Room did not start, is not steerable.
        var idle = agent; idle.state = "idle"
        XCTAssertFalse(idle.steerable)
        var desktop = agent; desktop.canSteer = false
        XCTAssertFalse(desktop.steerable)
        // A malformed limit is dropped without hiding the teammate.
        let broken = try JSONDecoder().decode(Agent.self, from: Data(#"{"id":"x","label":"X","limit":"oops","usage":{"monthly":"bad"}}"#.utf8))
        XCTAssertNil(broken.limit)
        XCTAssertNil(broken.usage?.monthly)
    }

    /// 1.3: the API-credit budget decodes field by field; bad values are dropped and never hide the teammate.
    func testBudgetDecodesAndToleratesBadValues() throws {
        let json = #"{"id":"claude-rigel","label":"Rigel","worker":"rigel","usage":{"balance":{"available":true,"currency":"USD","total":"198.80"},"budget":{"kind":"api-credit","currency":"USD","model":"claude-sonnet-5-5","effort":"high","pacing":"carry","today":{"day":"2026-10-27","spent":1.2,"cap":9.25,"left":8.05},"cycle":{"start":"2026-10-23T00:00:00.000Z","renewsAt":"2026-11-14T00:00:00.000Z","credit":200,"spent":32.4,"left":167.6,"daysLeft":18},"history":[{"day":"2026-10-26","spent":7.85},{"day":"2026-10-27","spent":1.2}],"lastRunAt":null}}}"#
        let agent = try JSONDecoder().decode(Agent.self, from: Data(json.utf8))
        let budget = try XCTUnwrap(agent.usage?.budget)
        XCTAssertEqual(budget.todayLine, "Today $1.20 / $9.25")
        XCTAssertEqual(budget.cycleLine, "This cycle $32.40 of $200 · renews Nov 14")
        XCTAssertEqual(budget.history.map(\.spent), [7.85, 1.2])
        XCTAssertTrue(budget.showsToday && budget.showsCycle)
        XCTAssertNotNil(agent.usage?.balance, "the balance chip data still decodes next to the budget")
        // Wrong types: numbers as text are read, junk is dropped, a day with no name is skipped, the agent stays.
        let bad = #"{"id":"x","label":"X","usage":{"budget":{"currency":5,"today":{"spent":"2.50","cap":"oops"},"cycle":"nope","history":[{"day":"2026-10-27","spent":"bad"},{"spent":3},7]}}}"#
        let broken = try JSONDecoder().decode(Agent.self, from: Data(bad.utf8))
        XCTAssertEqual(broken.usage?.budget?.today?.spent, 2.5)
        XCTAssertNil(broken.usage?.budget?.today?.cap)
        XCTAssertNil(broken.usage?.budget?.cycle)
        XCTAssertEqual(broken.usage?.budget?.history.map(\.day), ["2026-10-27"])
        XCTAssertFalse(broken.usage?.budget?.showsToday ?? true)
        let worse = try JSONDecoder().decode(Agent.self, from: Data(#"{"id":"y","label":"Y","usage":{"budget":"oops","monthly":5}}"#.utf8))
        XCTAssertNil(worse.usage?.budget)
        XCTAssertEqual(worse.usage?.monthly, 5)
    }

    /// 1.3: the update answer needs a usable build; the install link must be itms-services or https.
    func testAppUpdateAnswerDecodes() throws {
        let full = try JSONDecoder().decode(AppUpdateInfo.self, from: Data(#"{"build":16,"version":"1.3.1","notes":"Fixes","installUrl":"itms-services://?action=download-manifest&url=https%3A%2F%2Fpc.example%2Fm.plist"}"#.utf8))
        XCTAssertEqual(full.build, 16)
        XCTAssertEqual(full.installLink?.scheme, "itms-services")
        let textOnly = try JSONDecoder().decode(AppUpdateInfo.self, from: Data(#"{"build":"17","version":"1.3.2","installUrl":"javascript:alert(1)"}"#.utf8))
        XCTAssertEqual(textOnly.build, 17)
        XCTAssertNil(textOnly.installLink)
        XCTAssertThrowsError(try JSONDecoder().decode(AppUpdateInfo.self, from: Data(#"{"version":"1.3.2"}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(AppUpdateInfo.self, from: Data("<html>".utf8)))
    }

    func testLiveFramesDecodeTeamRoomAndActivityShapesLossily() throws {
        let team = try JSONDecoder().decode(LiveFrame.self, from: Data(#"{"type":"team","revision":9,"agents":[{"id":"gpt-assets","label":"GPT Plus","name":"Scout","rev":4,"waiting":2},{"label":"broken"}]}"#.utf8))
        XCTAssertEqual(team.agents?.map(\.id), ["gpt-assets"])
        XCTAssertEqual(team.agents?.first?.displayName, "Scout")
        let room = try JSONDecoder().decode(LiveFrame.self, from: Data(#"{"type":"room","message":{"id":"a1","role":"coordinator","state":"answering","responder":"polaris","text":"Hel","claim":{"responder":"polaris","reason":"Polaris is answering because Nova is on a hold until 2:40 AM CST."}}}"#.utf8))
        XCTAssertEqual(room.message?.responder, "polaris")
        XCTAssertTrue(room.message?.claimWorthShowing == true)
        XCTAssertTrue(room.message?.isInProgress == true)
    }

    func testTeamSnapshotKeepsGoodTeammatesWhenOneIsMalformed() throws {
        let data = Data(#"{"apiVersion":2,"revision":3,"publicOrigins":["https://teamroom.example.ts.net:8443"],"coordinators":[{"name":"polaris","label":"Polaris","available":true}],"agents":[{"id":"claude-polaris","label":"Polaris","quota":{"fiveHourStop":85,"weeklyStop":95,"held":false}},{"nope":true},{"id":"claude-adventure","label":"Claude Max Review","name":"Sage","usage":{"weekly":"bad"}}]}"#.utf8)
        let snapshot = try JSONDecoder().decode(TeamSnapshot.self, from: data)
        XCTAssertEqual(snapshot.agents.map(\.id), ["claude-polaris", "claude-adventure"])
        XCTAssertEqual(snapshot.agents[0].quota?.fiveHourStop, 85)
        XCTAssertNil(snapshot.agents[1].usage)
        XCTAssertEqual(snapshot.agents[1].displayName, "Sage")
        XCTAssertEqual(snapshot.coordinators.first?.label, "Polaris")
    }

    // MARK: - Board (1.2)

    func testGoalsDecodeTheirTrackAndGroupIntoWeightedTracks() throws {
        let json = #"[{"id":"world","title":"Ten-region world","percent":38,"weight":15,"track":"ten-region"},{"id":"economy","title":"Economy rework","percent":5,"weight":15,"track":"pack"},{"id":"quests","title":"Quests","percent":57,"weight":15,"track":"ten-region"},{"id":"loose","title":"No track","percent":10}]"#
        let goals = try JSONDecoder().decode([Goal].self, from: Data(json.utf8))
        XCTAssertEqual(goals.map(\.track), ["ten-region", "pack", "ten-region", nil])
        let tracks = GoalTrack.group(goals)
        XCTAssertEqual(tracks.map(\.id), ["ten-region", "pack", ""])
        XCTAssertEqual(tracks[0].goals.map(\.id), ["world", "quests"])
        XCTAssertEqual(tracks[0].percent, 48, "(38 x 15 + 57 x 15) / 30 = 47.5, rounded like the PC")
        XCTAssertEqual(tracks[1].percent, 5)
        XCTAssertEqual(tracks[2].title, "Other goals")
        XCTAssertEqual(GoalTrack.group(goals.map { var goal = $0; goal.track = nil; return goal }).count, 1, "a plan without tracks is one list")
    }

    func testGoalTrackWeightsAndValuesAreReadLikeThePC() throws {
        let json = #"[{"id":"economy","title":"Economy rework","percent":5,"weight":"15","track":"pack"},{"id":"zero","title":"Zero weight","percent":100,"weight":0,"track":"pack"},{"id":"odd","title":"Odd track","percent":50,"track":7}]"#
        let goals = try JSONDecoder().decode([Goal].self, from: Data(json.utf8))
        XCTAssertEqual(goals.map(\.id), ["economy", "zero", "odd"], "a hand-edited weight or track keeps the goal")
        XCTAssertEqual(goals[0].weight, 15)
        XCTAssertNil(goals[2].track)
        XCTAssertEqual(GoalTrack.group(goals)[0].percent, 11, "(5 x 15 + 100 x 1) / 16: a weight of 0 counts as 1, like the PC")
    }

    // MARK: - Navigation, notes, stores

    @MainActor func testDeepLinksFromNotificationsOpenTheRightScreen() {
        let router = Router()
        XCTAssertTrue(router.open(URL(string: "teamroom://agent/claude-assets")!))
        XCTAssertEqual(router.tab, .agents)
        XCTAssertEqual(router.agentPath, ["claude-assets"])
        XCTAssertTrue(router.open(URL(string: "teamroom://chat/answer-1")!))
        XCTAssertEqual(router.tab, .team)
        XCTAssertEqual(router.focusRoomMessage, "answer-1")
        XCTAssertTrue(router.open(URL(string: "teamroom://notes/note-1")!))
        XCTAssertEqual(router.tab, .notes)
        XCTAssertEqual(router.openNoteId, "note-1")
        XCTAssertTrue(router.open(URL(string: "teamroom://settings")!))
        XCTAssertTrue(router.showSettings)
        XCTAssertTrue(router.open(URL(string: "teamroom://pair?link=https%3A%2F%2Fpc.example%2F%23pair%3Dabc")!))
        XCTAssertEqual(router.pendingPairLink, "https://pc.example/#pair=abc")
        XCTAssertFalse(router.open(URL(string: "https://example.com")!))
    }

    @MainActor func testNotesMergeKeepsNewerLocalEditsAndTakesNewerServerCopies() {
        let store = NotesStore()
        store.notes = [
            Note(id: "note-a", text: "local newer", updatedAt: "2026-10-02T03:00:00.000Z", pendingSync: true),
            Note(id: "note-b", text: "local older", updatedAt: "2026-10-02T01:00:00.000Z", pendingSync: true),
            Note(id: "note-c", text: "synced", updatedAt: "2026-10-01T01:00:00.000Z")
        ]
        store.merge(server: [
            Note(id: "note-a", text: "server older", updatedAt: "2026-10-02T02:00:00.000Z"),
            Note(id: "note-b", text: "server newer", updatedAt: "2026-10-02T02:00:00.000Z"),
            Note(id: "note-d", text: "Shared priorities\nUnova first", shared: true, updatedAt: "2026-10-02T02:30:00.000Z")
        ])
        XCTAssertEqual(store.note("note-a")?.text, "local newer")
        XCTAssertEqual(store.note("note-b")?.text, "server newer")
        XCTAssertEqual(store.note("note-d")?.displayTitle, "Shared priorities")
        XCTAssertEqual(store.note("note-d")?.preview, "Unova first")
        XCTAssertEqual(store.visible.first?.id, "note-a")
    }

    @MainActor func testConversationStoreHidesStreamedTextOnceSavedAndResyncsOnGap() throws {
        let store = ConversationStore(agentId: "claude-assets")
        store.apply(ConversationPayload(agentId: "claude-assets", rev: 2, messages: [ChatMessage(id: "m1", role: "assistant", text: "Done.", time: "2026-10-02T03:00:00Z")], liveText: "Done."), etag: "W/\"2.5\"")
        XCTAssertNil(store.visibleLiveText)
        XCTAssertEqual(store.rev, 2)
        let gap = try JSONDecoder().decode(LiveFrame.self, from: Data(#"{"type":"stream","agentId":"claude-assets","base":99,"append":"x"}"#.utf8))
        XCTAssertFalse(store.applyStream(gap))
    }

    @MainActor func testTeamStoreOnlyPublishesRealChanges() {
        let store = TeamStore()
        let agent = Agent(id: "a", label: "A", state: "idle")
        store.replace([agent])
        var activity = LiveFrame(type: "activity")
        activity.agentId = "a"
        activity.state = "working"
        store.applyActivity(activity)
        XCTAssertEqual(store.agent("a")?.state, "working")
        XCTAssertEqual(store.workingCount, 1)
    }

    func testFastTimestampParserMatchesTheSystemFormatter() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        for value in ["2026-10-02T03:30:00.000Z", "2026-02-28T23:59:59.999Z", "2024-02-29T12:00:00.5Z", "1999-12-31T00:00:00.123456Z"] {
            XCTAssertEqual(TimeFormat.fastUTC(value)!.timeIntervalSince1970, formatter.date(from: value)!.timeIntervalSince1970, accuracy: 0.001, value)
        }
        XCTAssertEqual(TimeFormat.fastUTC("2026-10-02T03:30:00Z")!.timeIntervalSince1970, plain.date(from: "2026-10-02T03:30:00Z")!.timeIntervalSince1970)
        XCTAssertNil(TimeFormat.fastUTC("2026-10-02T03:30:00+02:00"), "offsets fall back to the formatter")
        XCTAssertNotNil(TimeFormat.date("2026-10-02T03:30:00+02:00"))
        XCTAssertNil(TimeFormat.fastUTC("not a date at all!!!"))
    }

    // MARK: - Performance (numbers land in the CI log and the QA report)

    func testPerformanceBuildingALongConversation() {
        let messages = (0..<600).map { ChatMessage(id: "m\($0)", role: $0 % 2 == 0 ? "user" : "assistant", text: "Message \($0)", time: String(format: "2026-10-01T%02d:%02d:00Z", ($0 / 60) % 24, $0 % 60)) }
        let events = (0..<1400).map { LiveEvent(id: "e\($0)", kind: "tool", title: "Command · step \($0)", time: String(format: "2026-10-01T%02d:%02d:30Z", ($0 / 60) % 24, $0 % 60), status: "completed", action: "command") }
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            _ = ConversationBuilder.items(messages: messages, events: events)
        }
    }

    func testPerformanceRenderingLongMarkdown() {
        let section = "## Section\n\nA paragraph with **bold**, `code` and a [link](https://example.com).\n\n- one\n- two\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\n"
        let texts = (0..<40).map { String(repeating: section, count: 6) + "\($0)" }
        measure(metrics: [XCTClockMetric()]) {
            for text in texts { _ = RenderedMarkdown(text) }
        }
    }

    func testPerformanceDecodingAConversationPayload() throws {
        let messages = (0..<100).map { index -> [String: Any] in
            ["id": "m\(index)", "role": index % 2 == 0 ? "user" : "assistant", "text": String(repeating: "word ", count: 300), "time": "2026-10-01T10:00:00Z"]
        }
        let events = (0..<200).map { index -> [String: Any] in
            ["id": "e\(index)", "kind": "tool", "title": "Read · file\(index).md", "time": "2026-10-01T10:00:00Z", "status": "completed", "detailPreview": String(repeating: "x", count: 100)]
        }
        let data = try JSONSerialization.data(withJSONObject: ["agentId": "a", "rev": 1, "messages": messages, "events": events, "queue": [], "prompts": []])
        measure(metrics: [XCTClockMetric()]) {
            _ = try? JSONDecoder().decode(ConversationPayload.self, from: data)
        }
    }
}
