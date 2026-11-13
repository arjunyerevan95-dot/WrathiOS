import XCTest
final class InputUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func dismissKeyboardTutorial(_ app: XCUIApplication) {
        // Fresh iOS Simulator keyboards cover the keys with this one-time
        // QuickPath explanation. Dismiss only that observed non-binding notice.
        let notice = app.staticTexts["Speed up your typing by sliding your finger across the letters to compose a word."]
        if notice.waitForExistence(timeout: 2) { app.buttons["Continue"].tap() }
    }
    func testManualKeyboardInSDLHostLoop() {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.buttons["WrathKeyboardButton"].waitForExistence(timeout: 10))
        for name in ["FIRE", "ALT", "JUMP", "CROUCH", "USE", "NEXT WEP",  "USE ART","USE ART", "ACTIONS", "SETTINGS"] {
            XCTAssertTrue(app.buttons["WrathAction_" + name].exists, "Menu cluster: " + name)
        }
        app.buttons["WrathAction_FIRE"].tap()
        app.buttons["WrathKeyboardButton"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8))
        dismissKeyboardTutorial(app)
        for key in "wrath" { app.keyboards.keys[String(key)].tap() }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
        sleep(1)
    }
    func testAutomaticProfileKeyboardInSDLHostLoop() {
        let app = XCUIApplication(); app.launchArguments = ["--profile"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        dismissKeyboardTutorial(app)
        for key in "profile" { app.keyboards.keys[String(key)].tap() }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
    }
    func testGameplayClusterSurvivesRepeatedFrames() {
        let app = XCUIApplication(); app.launchArguments = ["--gameplay"]
        XCUIDevice.shared.orientation = .landscapeLeft; app.launch()
        for name in ["FIRE","ALT","JUMP","CROUCH","USE","NEXT WEP","USE ART","ACTIONS","SETTINGS"] {
            XCTAssertTrue(app.buttons["WrathAction_" + name].waitForExistence(timeout: 10), name)
        }
        let fire = app.buttons["WrathAction_FIRE"].frame
        let use = app.buttons["WrathAction_USE"].frame
        XCTAssertLessThan(use.maxY + 8, fire.minY, "Use must sit above Fire with spacing")
        XCTAssertGreaterThan(fire.width, use.width, "Fire must remain the primary target")
        sleep(2)
        XCTAssertTrue(app.buttons["WrathAction_FIRE"].exists)
        app.buttons["WrathAction_FIRE"].tap()
        app.buttons["WrathAction_JUMP"].tap()
        let fireStart = app.buttons["WrathAction_FIRE"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let fireEnd = fireStart.withOffset(CGVector(dx: -90, dy: 30))
        fireStart.press(forDuration: 0.15, thenDragTo: fireEnd)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.60, dy: 0.80))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.80, dy: 0.80))
        start.press(forDuration: 0.05, thenDragTo: end)
        app.buttons["WrathAction_SETTINGS"].tap()
        XCTAssertTrue(app.sliders.firstMatch.waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
    }
}
