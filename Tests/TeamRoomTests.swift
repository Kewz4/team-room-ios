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
