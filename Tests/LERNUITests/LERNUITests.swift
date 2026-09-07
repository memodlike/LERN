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
    @MainActor func enter(_ value: String, into field: XCUIElement, app: XCUIApplication) {
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let words = value.split(separator: " ", omittingEmptySubsequences: false)
        for (index, word) in words.enumerated() { field.typeText((index == 0 ? "" : " ") + word) }
        XCTAssertEqual(field.value as? String, value)
    }
    @MainActor func testCreateReadFavoriteAndSettings() throws {
        let app = application()
        XCTAssertTrue(app.buttons["Write a thought"].waitForExistence(timeout: 20))
        capture(app, "First launch")
        app.buttons["Write a thought"].tap()
        let text = app.textViews["editor.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5)); enter("A local thought for the QA journey.", into: text, app: app)
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
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "60 / 60")).firstMatch.waitForExistence(timeout: 20))
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
    @MainActor func testCollectionSharingAndPersistence() throws {
        let app = application()
        XCTAssertTrue(app.buttons["Write a thought"].waitForExistence(timeout: 20)); app.buttons["Write a thought"].tap()
        let editor = app.textViews["editor.text"]; XCTAssertTrue(editor.waitForExistence(timeout: 5))
        enter("Keep this thought after restarting LERN.", into: editor, app: app)
        app.buttons["editor.save"].tap()
        XCTAssertTrue(app.staticTexts["feed.quote"].waitForExistence(timeout: 10))
        app.buttons["More actions"].tap(); app.buttons["Add to collection"].tap()
        let name = app.textFields["New collection name"]; XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("QA collection"); app.buttons["Create and add"].tap()
        XCTAssertTrue(app.buttons["Share"].waitForExistence(timeout: 10)); app.buttons["Share"].tap()
        XCTAssertTrue(app.images["share.preview"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Share image"].isEnabled)
        capture(app, "Share image preview")
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["feed.quote"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts["feed.quote"].label, "Keep this thought after restarting LERN.")
        app.buttons["feed.library"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("Keep this thought")
        XCTAssertTrue(app.staticTexts["Keep this thought after restarting LERN."].waitForExistence(timeout: 10))
        capture(app, "Library search")
    }
    @MainActor func testIndependentWallpaperSourcePersists() throws {
        let app = application()
        XCTAssertTrue(app.buttons["Try original sample thoughts"].waitForExistence(timeout: 20)); app.buttons["Try original sample thoughts"].tap()
        XCTAssertTrue(app.buttons["Profile"].waitForExistence(timeout: 15)); app.buttons["Profile"].tap()
        for _ in 0..<5 { if app.buttons["Wallpapers"].isHittable { break }; app.swipeUp() }
        app.buttons["Wallpapers"].tap(); app.buttons["Type of Content"].tap()
        let own = app.switches["My Content"]; XCTAssertTrue(own.waitForExistence(timeout: 5)); own.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Type of Content"].tap()
        XCTAssertEqual(app.switches["My Content"].value as? String, "1")
        capture(app, "Independent wallpaper source")
    }

}
