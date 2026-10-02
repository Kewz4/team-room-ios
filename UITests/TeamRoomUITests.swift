import XCTest

/// Screen-by-screen QA with populated fixtures (the real team, the real board numbers). Every screen is captured
/// as an attachment; CI exports them so each build has its own populated screenshots, light, dark and large text.
final class TeamRoomUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + extra
        app.launch()
        return app
    }

    private func text(_ app: XCUIApplication, containing value: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", value)).firstMatch
    }

    func testTeamChatShowsAnswersHandOverAndStreaming() {
        let app = launch()
        XCTAssertTrue(text(app, containing: "Here's the team right now").waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Why Nova answered"].waitForExistence(timeout: 5), "a hand-over explains who answered")
        XCTAssertTrue(text(app, containing: "Reading PLAN.json").exists, "the answer in progress shows what the coordinator is doing")
        capture("01-team-chat", app)
        app.buttons["Why Nova answered"].tap()
        XCTAssertTrue(text(app, containing: "Polaris is answering another question").waitForExistence(timeout: 5))
        capture("02-team-chat-handover", app)
        XCTAssertTrue(app.buttons["Stop answer"].exists, "the send button turns into stop while a coordinator answers")
    }

    func testEmptyTeamChatOffersSuggestions() {
        let app = launch(["-ui-empty-chat"])
        XCTAssertTrue(text(app, containing: "Ask the team anything").waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.matching(identifier: "suggestion").firstMatch.exists)
        capture("03-team-chat-empty", app)
    }

    func testAgentsListAndRoomWithTableImageAndReport() {
        let app = launch(["-ui-open-agents"])
        let nova = app.buttons["agent-row-claude-assets"]
        XCTAssertTrue(nova.waitForExistence(timeout: 10))
        XCTAssertTrue(text(app, containing: "Nova needs your input").exists)
        capture("04-agents", app)
        nova.tap()
        let picture = app.buttons["Fixture artwork"]
        XCTAssertTrue(picture.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["markdown-table"].exists)
        capture("05-agent-room", app)
        let scroll = app.scrollViews["conversation-scroll"]
        scroll.swipeDown(velocity: .fast)
        scroll.swipeDown(velocity: .fast)
        let latest = app.buttons["jump-latest"]
        XCTAssertTrue(latest.waitForExistence(timeout: 5))
        latest.tap()
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: picture)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 8), .completed)
        picture.tap()
        XCTAssertTrue(app.buttons["Zoom in"].waitForExistence(timeout: 5))
        app.buttons["Zoom in"].tap()
        XCTAssertEqual(app.staticTexts["image-zoom-level"].label, "150%")
        capture("06-image-zoom", app)
        app.buttons["Fit image"].tap()
        XCTAssertEqual(app.staticTexts["image-zoom-level"].label, "100%")
        app.buttons["Close image"].tap()
        app.links["Open fixture report"].tap()
        XCTAssertTrue(app.staticTexts["Fixture report preview"].waitForExistence(timeout: 5))
        capture("07-report-preview", app)
        app.buttons["Done"].tap()
    }

    func testBoardOverviewChartsWorkAndGoalDetail() {
        let app = launch(["-ui-open-board"])
        XCTAssertTrue(text(app, containing: "ten-region phase").waitForExistence(timeout: 10))
        XCTAssertTrue(text(app, containing: "Waiting on you").exists)
        capture("08-board-overview", app)
        app.swipeUp()
        capture("09-board-goals", app)
        app.swipeUp()
        capture("10-board-charts", app)
        app.swipeUp()
        app.swipeUp()
        capture("11-board-work", app)
        app.swipeDown()
        app.swipeDown()
        app.swipeDown()
        let goal = app.buttons["goal-engine"]
        if goal.waitForExistence(timeout: 5) {
            goal.tap()
            XCTAssertTrue(text(app, containing: "N8 save-guard correction").waitForExistence(timeout: 5))
            capture("12-goal-detail", app)
        }
    }

    func testNotesListAndEditor() {
        let app = launch(["-ui-open-notes"])
        XCTAssertTrue(text(app, containing: "Priorities this week").waitForExistence(timeout: 10))
        capture("13-notes", app)
        app.buttons["new-note"].tap()
        let editor = app.textViews["note-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText("Groceries\nmilk, eggs")
        capture("14-note-editor", app)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(text(app, containing: "Groceries").waitForExistence(timeout: 5))
    }

    func testInboxSettingsAndBarkSetup() {
        let app = launch(["-ui-open-inbox"])
        XCTAssertTrue(text(app, containing: "Nova is waiting for your answer").waitForExistence(timeout: 10))
        capture("15-inbox", app)
        app.buttons["settings-button"].firstMatch.tap()
        XCTAssertTrue(app.buttons["bark-setup"].waitForExistence(timeout: 5))
        capture("16-settings", app)
        app.buttons["bark-setup"].tap()
        XCTAssertTrue(text(app, containing: "Paste your Bark key").waitForExistence(timeout: 5))
        capture("17-bark-setup", app)
    }

    func testDarkModeAndLargeText() {
        var app = launch(["-ui-dark"])
        XCTAssertTrue(text(app, containing: "Here's the team right now").waitForExistence(timeout: 10))
        capture("18-dark-team-chat", app)
        app.terminate()
        app = launch(["-ui-dark", "-ui-open-board"])
        XCTAssertTrue(text(app, containing: "ten-region phase").waitForExistence(timeout: 10))
        capture("19-dark-board", app)
        app.terminate()
        app = launch(["-ui-large-type", "-ui-open-agents"])
        XCTAssertTrue(app.buttons["agent-row-claude-assets"].waitForExistence(timeout: 10))
        capture("20-large-type-agents", app)
    }

    func testFailedDeliverySwipeEditDeleteAndUndo() {
        let app = launch(["-ui-open-nova"])
        XCTAssertTrue(app.buttons["More"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["More"].firstMatch.tap()
        app.buttons["Delivery queue"].tap()
        let row = app.cells.containing(.staticText, identifier: "delivery-body-fixture-failed").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeRight()
        app.buttons["Edit"].tap()
        let editor = app.textViews["delivery-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(" revised")
        app.buttons["Save changes"].tap()
        let editorDismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: editor)
        XCTAssertEqual(XCTWaiter.wait(for: [editorDismissed], timeout: 8), .completed)
        XCTAssertTrue(app.staticTexts["Edited · ready to retry"].waitForExistence(timeout: 5))
        let body = app.staticTexts["delivery-body-fixture-failed"]
        let bodyVisible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: body)
        XCTAssertEqual(XCTWaiter.wait(for: [bodyVisible], timeout: 5), .completed)
        body.swipeLeft()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 5))
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["Undo delete"].waitForExistence(timeout: 5))
        capture("21-delivery-delete-undo", app)
        app.buttons["Undo delete"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }

    // MARK: - Performance

    func testScrollHitchesInALongConversation() {
        let app = launch(["-ui-open-nova"])
        let scroll = app.scrollViews["conversation-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStop]
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric], options: options) {
            scroll.swipeDown(velocity: .fast)
            stopMeasuring()
            scroll.swipeUp(velocity: .fast)
        }
    }

    func testLaunchTime() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
        }
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
