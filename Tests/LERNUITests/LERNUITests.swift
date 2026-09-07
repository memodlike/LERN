import XCTest

final class LERNUITests: XCTestCase {
    @MainActor func application(language: String = "en", largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LERN_UI_TEST_SESSION"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", language == "ru" ? "ru_RU" : "en_US"]
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch(); return app
    }
    @MainActor func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor func testCreateReadFavoriteAndSettings() throws {
        let app = application()
        XCTAssertTrue(app.buttons["Write a thought"].waitForExistence(timeout: 20))
        capture(app, "First launch")
        app.buttons["Write a thought"].tap()
        let text = app.textViews["editor.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5)); text.tap(); text.typeText("A local thought for the QA journey.")
        app.buttons["editor.save"].tap()
        XCTAssertTrue(app.staticTexts["feed.quote"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["feed.quote"].label, "A local thought for the QA journey.")
        app.buttons["feed.favorite"].tap()
        XCTAssertTrue(app.buttons["Remove favorite"].waitForExistence(timeout: 5))
        capture(app, "Reading feed")
        app.buttons["Themes"].tap()
        XCTAssertTrue(app.navigationBars["Themes"].waitForExistence(timeout: 5))
        capture(app, "Themes")
    }
    @MainActor func testRemindersAndSourceIsolation() throws {
        let app = application()
        XCTAssertTrue(app.buttons["Try original sample thoughts"].waitForExistence(timeout: 20))
        app.buttons["Try original sample thoughts"].tap()
        XCTAssertTrue(app.staticTexts["feed.quote"].waitForExistence(timeout: 15))
        app.buttons["Reminders"].tap()
        if app.buttons["Enable notifications"].waitForExistence(timeout: 5) {
            app.buttons["Enable notifications"].tap()
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            if springboard.buttons["Allow"].waitForExistence(timeout: 5) { springboard.buttons["Allow"].tap() }
        }
        app.buttons["reminders.add"].tap()
        XCTAssertTrue(app.navigationBars["Reminder group"].waitForExistence(timeout: 5))
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["60 / 60"].waitForExistence(timeout: 20))
        capture(app, "Scheduled reminders")
    }
    @MainActor func testRussianAndLargeText() throws {
        let app = application(language: "ru", largeText: true)
        XCTAssertTrue(app.buttons["Импорт файлов"].waitForExistence(timeout: 20))
        capture(app, "Russian large text")
        XCUIDevice.shared.orientation = .landscapeLeft
        capture(app, "Russian landscape")
        XCUIDevice.shared.orientation = .portrait
    }
}
