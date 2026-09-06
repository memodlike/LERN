import XCTest

final class LERNUITests: XCTestCase {
    @MainActor func testCreateReadFavoriteAndSettings() throws {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["Write a thought"].waitForExistence(timeout: 20))
        app.buttons["Write a thought"].tap()
        let text = app.textViews["editor.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5)); text.tap(); text.typeText("A local thought for the QA journey.")
        app.buttons["editor.save"].tap()
        XCTAssertTrue(app.staticTexts["feed.quote"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["feed.quote"].label, "A local thought for the QA journey.")
        app.buttons["feed.favorite"].tap()
        XCTAssertTrue(app.buttons["Remove favorite"].waitForExistence(timeout: 5))
        app.buttons["Themes"].tap()
        XCTAssertTrue(app.navigationBars["Themes"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Themes"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
