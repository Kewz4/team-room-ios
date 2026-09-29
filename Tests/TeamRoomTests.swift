import XCTest
@testable import TeamRoom

final class TeamRoomTests: XCTestCase {
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

    func testDeliveredUserPromptPrecedesToolsAndNativeCopyIsNotDuplicated() {
        let sent = "2026-09-29T21:00:00.000Z"
        let queued = ChatMessage(id: "run", text: "Check this task", createdAt: sent, sentAt: sent, state: "streaming")
        let tool = LiveEvent(id: "tool", kind: "tool", title: "Read files", time: sent, status: "running")
        let fallback = ConversationBuilder.items(messages: [], events: [tool], queue: [queued])
        XCTAssertEqual(fallback.map(\.id), ["m:run", "g:tool"])
        let native = ChatMessage(id: "native", role: "user", text: "Check this task", time: sent)
        let merged = ConversationBuilder.items(messages: [native], events: [tool], queue: [queued])
        XCTAssertEqual(merged.map(\.id), ["m:native", "g:tool"])
    }

    func testTimelineKeepsAssistantAfterToolForTimestampTies() {
        let time = "2026-09-29T21:00:00Z"
        let messages = [ChatMessage(id: "answer", role: "assistant", text: "Result", time: time), ChatMessage(id: "user", role: "user", text: "Task", time: time)]
        let events = [LiveEvent(id: "command", kind: "tool", title: "Command", time: time)]
        XCTAssertEqual(ConversationBuilder.items(messages: messages, events: events).map(\.id), ["m:user", "g:command", "m:answer"])
    }

    func testNoticeLedgerBaselinesOnceDeduplicatesAndSurvivesReconnect() throws {
        func agent(_ event: String) -> Agent {
            Agent(id: "a", label: "Astra", state: "idle", statusSummary: TaskStatus(kind: "completed", label: "Finished", eventId: event))
        }
        var ledger = NoticeLedger()
        XCTAssertTrue(ledger.consume([agent("old")]).isEmpty)
        XCTAssertEqual(ledger.consume([agent("new")]).count, 1)
        XCTAssertTrue(ledger.consume([agent("new")]).isEmpty)
        let data = try JSONEncoder().encode(ledger)
        var restored = try JSONDecoder().decode(NoticeLedger.self, from: data)
        XCTAssertTrue(restored.consume([agent("new")]).isEmpty)
        XCTAssertEqual(restored.consume([agent("offline-completion")]).count, 1)
        XCTAssertEqual(restored.notices.count, 2)
    }

    func testWorkingStateCannotBeOverriddenByStaleFinishedSummary() {
        let a = Agent(id: "a", label: "A", state: "working", statusSummary: TaskStatus(kind: "completed", label: "Finished", eventId: "old"))
        XCTAssertEqual(a.taskStatus.kind, "working")
    }
}
