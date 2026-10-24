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

    private func anyElement(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Drags a third of the screen at a time, holding before lifting so nothing flings past (lazy sections only exist
    /// once scrolled near), until the element's top sits under the navigation bar in the upper half of the screen,
    /// or the list cannot scroll further. True when the element's top is then on screen.
    @discardableResult
    private func scroll(to element: XCUIElement, _ app: XCUIApplication, up: Bool = true, swipes: Int = 12) -> Bool {
        let window = app.windows.firstMatch.frame
        func top() -> CGFloat? { element.exists && !element.frame.isEmpty ? element.frame.minY - window.minY : nil }
        func placed(_ y: CGFloat?) -> Bool { guard let y else { return false }; return y > window.height * 0.12 && y < window.height * 0.5 }
        var count = 0
        var last: CGFloat?
        while !placed(top()) && count < swipes {
            // Once the element is known, drag towards it: back down when its top is already above the band.
            var dragUp = up
            if let y = top() { dragUp = y >= window.height * 0.5 }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: dragUp ? 0.66 : 0.34))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: dragUp ? 0.34 : 0.66))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.2)
            count += 1
            let now = top()
            if let now, let last, abs(now - last) < 1 { break }
            last = now
        }
        guard let y = top() else { return false }
        return y > window.height * 0.1 && y < window.height * 0.92
    }

    /// 1.2: a focused text field shows the hide-keyboard button in the navigation bar, and the button puts it away.
    private func assertHideKeyboardButtonWorks(_ app: XCUIApplication, _ screenshot: String?) {
        let hide = app.buttons["hide-keyboard"]
        XCTAssertTrue(hide.waitForExistence(timeout: 5), "a visible hide-keyboard button while typing")
        if let screenshot { capture(screenshot, app) }
        hide.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: hide)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed, "the button goes away with the keyboard")
    }

    /// At the newest message there is nothing to jump to (1.0 review: the button showed at the bottom and in an empty chat).
    private func assertNoJumpButton(_ app: XCUIApplication, _ message: String) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["jump-latest"])
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 3), .completed, message)
    }

    func testTeamChatShowsAnswersHandOverAndStreaming() {
        let app = launch()
        XCTAssertTrue(text(app, containing: "Here's the team right now").waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Why Vega answered"].waitForExistence(timeout: 5), "a hand-over explains who answered")
        XCTAssertTrue(text(app, containing: "Reading PLAN.json").exists, "the answer in progress shows what the coordinator is doing")
        assertNoJumpButton(app, "following a streaming answer shows no jump-to-latest button")
        capture("01-team-chat", app)
        app.buttons["Why Vega answered"].tap()
        XCTAssertTrue(text(app, containing: "Polaris is answering another question").waitForExistence(timeout: 5))
        capture("02-team-chat-handover", app)
        XCTAssertTrue(app.buttons["Stop answer"].exists, "the send button turns into stop while a coordinator answers")
    }

    func testEmptyTeamChatOffersSuggestions() {
        let app = launch(["-ui-empty-chat"])
        XCTAssertTrue(text(app, containing: "Ask the team anything").waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.matching(identifier: "suggestion").firstMatch.exists)
        assertNoJumpButton(app, "an empty chat has nothing to jump to")
        capture("03-team-chat-empty", app)
        // 1.2: while typing, a visible button puts the keyboard away.
        let composer = anyElement(app, "team-composer")
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap()
        XCTAssertTrue(app.buttons["hide-keyboard"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertFalse(app.buttons["jump-latest"].exists, "an empty chat shows no jump button, even with the keyboard up")
        XCTAssertFalse(app.buttons["More"].exists, "while typing, the hide-keyboard button takes the More menu's place")
        assertHideKeyboardButtonWorks(app, "03b-team-chat-typing")
        XCTAssertTrue(app.buttons["More"].waitForExistence(timeout: 5), "the More menu returns with the keyboard put away")
    }

    func testAgentsListAndRoomWithTableImageAndReport() {
        let app = launch(["-ui-open-agents"])
        let nova = app.buttons["agent-row-claude-assets"]
        XCTAssertTrue(nova.waitForExistence(timeout: 10))
        XCTAssertTrue(text(app, containing: "Nova needs your input").exists)
        capture("04-agents", app)
        nova.tap()
        let picture = app.buttons["Fixture artwork"]
        if !picture.waitForExistence(timeout: 20) {
            capture("05-agent-room-missing-artwork", app)
            XCTFail("the room should open at its newest messages, which include the fixture artwork")
            return
        }
        XCTAssertTrue(app.descendants(matching: .any)["markdown-table"].exists)
        assertNoJumpButton(app, "a room opens at its newest message")
        capture("05-agent-room", app)
        // Drag in the messages above the pinned decision card: a swipe at the screen centre lands on the card and
        // scrolls nothing (1.0 review: the old swipe only "passed" because the button showed all the time).
        for _ in 0..<4 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.24))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.39)))
        }
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
        XCTAssertTrue(text(app, containing: "ten regions and a living").waitForExistence(timeout: 10))
        XCTAssertTrue(text(app, containing: "Waiting on you").exists)
        capture("08-board-overview", app)
        // 1.2: the team lanes list Vega and Orion; Nimbus retired.
        XCTAssertTrue(scroll(to: app.buttons["lane-claude-orion"], app), "Orion has a lane")
        XCTAssertTrue(app.buttons["lane-claude-vega"].exists, "Vega has a lane")
        XCTAssertFalse(app.buttons["lane-nimbus"].exists, "Nimbus retired")
        capture("09-board-team-lanes", app)
        // 1.2: the goals sit in the redrawn board's two tracks.
        XCTAssertTrue(scroll(to: anyElement(app, "track-ten-region"), app), "the ten-region track")
        XCTAssertTrue(text(app, containing: "Ten-region phase · 42%").exists)
        capture("10-board-track-ten-region", app)
        XCTAssertTrue(scroll(to: anyElement(app, "track-pack"), app), "the pack track")
        XCTAssertTrue(text(app, containing: "Pack improvements · 2%").exists)
        capture("11-board-track-pack", app)
        app.swipeUp()
        app.swipeUp()
        capture("11b-board-charts-and-work", app)
        let goal = app.buttons["goal-engine"]
        XCTAssertTrue(scroll(to: goal, app, up: false, swipes: 16) && goal.isHittable, "the engine goal can be opened")
        goal.tap()
        XCTAssertTrue(text(app, containing: "N8 save-guard correction").waitForExistence(timeout: 5))
        capture("12-goal-detail", app)
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
        // 1.2: the editor hides the tab bar; it must come back on the list.
        let tabBack = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: app.tabBars.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [tabBack], timeout: 5), .completed, "the tab bar comes back after the editor")
    }

    /// 1.2 (Kewz, 2026-10-04): "allow me to scroll down on the notes, there's a point where I can't scroll down" and
    /// "a button to hide the keyboard". The end of a long note is reachable with and without the keyboard.
    func testLongNoteReachesItsEndWithAndWithoutTheKeyboard() {
        let app = launch(["-ui-open-notes"])
        let row = text(app, containing: "Hoenn trip ideas")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let editor = app.textViews["note-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue((editor.value as? String)?.hasSuffix("Last line of the long note") == true, "the whole note is loaded")
        let tabBar = app.tabBars.firstMatch
        XCTAssertFalse(tabBar.exists && tabBar.isHittable, "the editor has the whole screen; no tab bar over the end of the note")
        XCTAssertLessThanOrEqual(editor.frame.maxY, app.windows.firstMatch.frame.maxY + 0.5, "the text view ends on screen")
        XCTAssertFalse(app.buttons["hide-keyboard"].exists, "no keyboard, no hide-keyboard button")
        for _ in 0..<8 { editor.swipeUp(velocity: .fast) }
        capture("24-long-note-end", app)

        // With the keyboard the text view ends above it, so the last line can still scroll into view.
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5), "the on-screen keyboard shows")
        let above = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in editor.frame.maxY <= keyboard.frame.minY + 1 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [above], timeout: 5), .completed, "the note ends above the keyboard, not under it")
        for _ in 0..<8 { editor.swipeUp(velocity: .fast) }
        capture("25-long-note-end-keyboard", app)
        assertHideKeyboardButtonWorks(app, nil)
        let keyboardGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: keyboard)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardGone], timeout: 5), .completed, "the keyboard is put away")
        capture("26-long-note-keyboard-hidden", app)
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
        XCTAssertTrue(text(app, containing: "ten regions and a living").waitForExistence(timeout: 10))
        capture("19-dark-board", app)
        app.terminate()
        app = launch(["-ui-large-type", "-ui-open-agents"])
        XCTAssertTrue(app.buttons["agent-row-claude-assets"].waitForExistence(timeout: 10))
        capture("20-large-type-agents", app)
        // 1.1: the lower cards carry the stress case from Kewz's phone (hold + queued + failed + three usage bars).
        app.swipeUp()
        capture("21-large-type-agents-lower", app)
    }

    /// 1.2 (Kewz, 2026-10-04): Vega and Orion have their own cards and colours; Nimbus retired and has none.
    func testVegaAndOrionCardsInAgentsList() {
        let app = launch(["-ui-open-agents"])
        XCTAssertTrue(app.buttons["agent-row-claude-assets"].waitForExistence(timeout: 10))
        XCTAssertTrue(scroll(to: app.buttons["agent-row-claude-vega"], app), "Vega should be listed with the other teammates")
        XCTAssertTrue(scroll(to: app.buttons["agent-row-claude-orion"], app), "Orion should be listed with the other teammates")
        XCTAssertFalse(app.buttons["agent-row-nimbus"].exists, "Nimbus retired")
        capture("23-agents-vega-orion", app)
    }

    /// 1.3 (Kewz, 2026-10-23): Rigel and Lyra show their API money, in the list and in the room, light and dark.
    func testApiWorkersShowTodayAndCycleSpend() {
        for dark in [false, true] {
            let suffix = dark ? "-dark" : ""
            let theme = dark ? ["-ui-dark"] : []
            var app = launch(["-ui-open-agents"] + theme)
            // Orion's row is below the fold, so a lazy list has not built it yet: wait for the first rows, then scroll.
            XCTAssertTrue(app.buttons["agent-row-claude-assets"].waitForExistence(timeout: 10))
            let rigel = app.buttons["agent-row-claude-rigel"]
            let reached = scroll(to: rigel, app)
            capture("30-agents-api-workers\(suffix)", app)
            XCTAssertTrue(reached, "Rigel should be listed")
            XCTAssertTrue(rigel.label.contains("Today $1.20 / $9.25"), "Rigel's card shows today's spend against its cap")
            app = launch(["-ui-open-rigel"] + theme)
            XCTAssertTrue(anyElement(app, "budget-panel").waitForExistence(timeout: 10))
            capture("31-rigel-room\(suffix)", app)
            app = launch(["-ui-open-rigel", "-ui-budget-open"] + theme)
            XCTAssertTrue(anyElement(app, "budget-chart").waitForExistence(timeout: 10))
            capture("32-rigel-room-chart\(suffix)", app)
            app = launch(["-ui-open-lyra", "-ui-budget-open"] + theme)
            XCTAssertTrue(anyElement(app, "budget-chart").waitForExistence(timeout: 10))
            capture("33-lyra-room-chart\(suffix)", app)
        }
    }

    /// 1.3: a newer build offered by the PC shows a banner with Install, and Settings lists the installed build.
    func testUpdateBannerAndSettingsVersion() {
        let app = launch(["-ui-open-agents", "-ui-update-banner"])
        XCTAssertTrue(anyElement(app, "update-banner").waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["update-install"].exists)
        capture("34-update-banner", app)
        app.buttons["settings-button"].tap()
        let installed = app.staticTexts["Installed"].waitForExistence(timeout: 5)
        capture("35-settings-update", app)
        XCTAssertTrue(installed, "Settings lists the installed version and build")
    }

    /// 1.1 steering: while a Team Room turn runs, the composer says the message goes into that turn.
    func testSteeringComposerOnARunningTurn() {
        let app = launch(["-ui-open-agents"])
        let polaris = app.buttons["agent-row-claude-polaris"]
        XCTAssertTrue(polaris.waitForExistence(timeout: 10))
        polaris.tap()
        let shown = app.descendants(matching: .any)["steer-hint"].waitForExistence(timeout: 10)
        capture(shown ? "22-steer-composer" : "22-steer-composer-hint-missing", app)
        // 1.2: the agent room's composer has the hide-keyboard button too.
        let composer = anyElement(app, "agent-composer")
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap()
        assertHideKeyboardButtonWorks(app, "22b-agent-room-typing")
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
