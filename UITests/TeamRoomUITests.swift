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
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
