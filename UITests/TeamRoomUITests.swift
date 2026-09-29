import XCTest

final class TeamRoomUITests: XCTestCase {
    func testLatestButtonTableAndImageZoom() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        let picture = app.buttons["Fixture artwork"]
        XCTAssertTrue(picture.waitForExistence(timeout: 10))
        let scroll = app.scrollViews["conversation-scroll"]
        scroll.swipeDown(velocity: .fast)
        scroll.swipeDown(velocity: .fast)
        let latest = app.buttons["jump-latest"]
        XCTAssertTrue(latest.waitForExistence(timeout: 5))
        latest.tap()
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: picture)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 8), .completed)
        XCTAssertTrue(app.descendants(matching: .any)["markdown-table"].exists)
        capture("conversation-tables-and-status", app)
        picture.tap()
        XCTAssertTrue(app.buttons["Zoom in"].waitForExistence(timeout: 5))
        app.buttons["Zoom in"].tap()
        XCTAssertEqual(app.staticTexts["image-zoom-level"].label, "150%")
        app.buttons["Zoom in"].tap()
        capture("image-zoom", app)
        app.buttons["Fit image"].tap()
        XCTAssertEqual(app.staticTexts["image-zoom-level"].label, "100%")
        app.buttons["Close image"].tap()
        app.links["Open fixture report"].tap()
        XCTAssertTrue(app.staticTexts["Fixture report preview"].waitForExistence(timeout: 5))
        capture("report-preview", app)
        app.buttons["Done"].tap()
    }

    func testFailedDeliverySwipeEditDeleteAndUndo() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        app.buttons["More"].firstMatch.tap()
        app.buttons["Delivery queue"].tap()
        let row = app.descendants(matching: .any).matching(identifier: "delivery-fixture-failed").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeRight()
        app.buttons["Edit"].tap()
        let editor = app.textViews["delivery-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(" revised")
        app.buttons["Save changes"].tap()
        row.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["Undo delete"].waitForExistence(timeout: 5))
        capture("delivery-delete-undo", app)
        app.buttons["Undo delete"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
