import XCTest
final class InputUITests: XCTestCase {
    func testManualKeyboardInSDLHostLoop() {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.buttons["WrathKeyboardButton"].waitForExistence(timeout: 10))
        for name in ["FIRE", "ALT", "JUMP", "CROUCH", "USE", "NEXT WEP", "PREV WEP", "ACTIONS", "SETTINGS"] {
            XCTAssertTrue(app.buttons["WrathAction_" + name].exists, "Menu cluster: " + name)
        }
        app.buttons["WrathAction_FIRE"].tap()
        app.buttons["WrathKeyboardButton"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8))
        for key in "wrath" { app.keyboards.keys[String(key)].tap() }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
        sleep(1)
    }
    func testAutomaticProfileKeyboardInSDLHostLoop() {
        let app = XCUIApplication(); app.launchArguments = ["--profile"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        for key in "profile" { app.keyboards.keys[String(key)].tap() }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
    }
    func testGameplayClusterSurvivesRepeatedFrames() {
        let app = XCUIApplication(); app.launchArguments = ["--gameplay"]
        XCUIDevice.shared.orientation = .landscapeLeft; app.launch()
        for name in ["FIRE","ALT","JUMP","CROUCH","USE","NEXT WEP","PREV WEP","ACTIONS","SETTINGS"] {
            XCTAssertTrue(app.buttons["WrathAction_" + name].waitForExistence(timeout: 10), name)
        }
        sleep(2)
        XCTAssertTrue(app.buttons["WrathAction_FIRE"].exists)
        app.buttons["WrathAction_FIRE"].tap()
        app.buttons["WrathAction_JUMP"].tap()
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.60, dy: 0.80))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.80, dy: 0.80))
        start.press(forDuration: 0.05, thenDragTo: end)
        app.buttons["WrathAction_SETTINGS"].tap()
        XCTAssertTrue(app.sliders.firstMatch.waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
    }
}
