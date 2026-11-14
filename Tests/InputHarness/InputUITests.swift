import XCTest
final class InputUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func dismissKeyboardTutorial(_ app: XCUIApplication) {
        // Fresh iOS Simulator keyboards cover the keys with this one-time
        // QuickPath explanation. Dismiss only that observed non-binding notice.
        let notice = app.staticTexts["Speed up your typing by sliding your finger across the letters to compose a word."]
        if notice.waitForExistence(timeout: 2) { app.buttons["Continue"].tap() }
    }
    func typeVisibleKeyboard(_ text: String, into app: XCUIApplication) {
        // SDL deliberately keeps its UITextField hidden/zero-sized. XCTest's
        // typeText requires an AX-focused text field and cannot target it.
        // Tap the real native keyboard using four observed row-anchor frames.
        // This still exercises UIKit -> SDL -> the exact text receipt assertions.
        let keys = app.keyboards.firstMatch.keys
        let q = keys["q"].frame, p = keys["p"].frame
        let a = keys["a"].frame, z = keys["z"].frame
        XCTAssertFalse(q.isEmpty); XCTAssertFalse(p.isEmpty)
        XCTAssertFalse(a.isEmpty); XCTAssertFalse(z.isEmpty)
        let pitch = (p.midX - q.midX) / 9
        XCTAssertGreaterThan(pitch, 0)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let appFrame = app.frame
        let rows: [(String, CGRect)] = [("qwertyuiop", q), ("asdfghjkl", a), ("zxcvbnm", z)]
        for character in text {
            var point: CGPoint?
            for (letters, anchor) in rows {
                if let column = Array(letters).firstIndex(of: character) {
                    point = CGPoint(x: anchor.midX + CGFloat(column) * pitch, y: anchor.midY)
                    break
                }
            }
            guard let point else { XCTFail("Unsupported keyboard character"); return }
            origin.withOffset(CGVector(dx: point.x - appFrame.minX,
                                       dy: point.y - appFrame.minY)).tap()
        }
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
        typeVisibleKeyboard("wrath", into: app)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
        sleep(1)
    }
    func testAutomaticProfileKeyboardInSDLHostLoop() {
        let app = XCUIApplication(); app.launchArguments = ["--profile"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        dismissKeyboardTutorial(app)
        typeVisibleKeyboard("profile", into: app)
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
    func testEditableLayoutPersistsAndResets() {
        let app = XCUIApplication(); app.launchArguments = ["--gameplay"]
        XCUIDevice.shared.orientation = .landscapeLeft; app.launch()
        func edit() {
            XCTAssertTrue(app.buttons["WrathAction_SETTINGS"].waitForExistence(timeout: 10))
            app.buttons["WrathAction_SETTINGS"].tap()
            app.buttons["Edit button positions"].tap()
            XCTAssertTrue(app.buttons["Reset"].waitForExistence(timeout: 5))
        }
        edit()
        app.buttons["Reset"].tap() // Isolate persisted simulator state, not production data.
        let fire = app.buttons["WrathAction_FIRE"]
        let baseline = fire.frame
        let start = fire.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: -60, dy: 30)))
        let size = app.sliders["WrathSelectedButtonSize"]
        XCTAssertTrue(size.isEnabled)
        size.adjust(toNormalizedSliderPosition: 0.75)
        app.buttons["Done"].tap()
        let moved = fire.frame
        XCTAssertGreaterThan(moved.width, baseline.width * 1.3)
        XCTAssertLessThan(moved.midX, baseline.midX - 40)
        XCTAssertGreaterThan(moved.midY, baseline.midY + 15)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["WrathAction_FIRE"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["WrathAction_FIRE"].frame.midX, moved.midX, accuracy: 2)
        XCTAssertEqual(app.buttons["WrathAction_FIRE"].frame.midY, moved.midY, accuracy: 2)
        XCTAssertEqual(app.buttons["WrathAction_FIRE"].frame.width, moved.width, accuracy: 2)
        edit(); app.buttons["Reset"].tap(); app.buttons["Done"].tap()
        XCTAssertEqual(app.buttons["WrathAction_FIRE"].frame.midX, baseline.midX, accuracy: 2)
        XCTAssertEqual(app.buttons["WrathAction_FIRE"].frame.midY, baseline.midY, accuracy: 2)
        XCTAssertEqual(app.buttons["WrathAction_FIRE"].frame.width, baseline.width, accuracy: 2)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
    }
}
