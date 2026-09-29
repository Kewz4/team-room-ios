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
