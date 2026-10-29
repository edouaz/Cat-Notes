import XCTest

@MainActor
final class GoodnotesUIIntegrationTests: XCTestCase {
    func testCreationReadOnlyPaletteAndLibraryList() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-openNotebooks", "()", "-activeNotebook", "", "-toolPaletteVisible", "YES", "-toolPaletteDock", "top"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["library.create"].waitForExistence(timeout: 10))
        app.buttons["library.create"].tap()
        let field = app.textFields["library.new.title"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Integration notebook")
        app.buttons["library.new.confirm"].tap()
        XCTAssertTrue(app.buttons["editor.readOnly"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["editor.tool.lasso"].exists)
        app.buttons["editor.readOnly"].tap()
        let toolGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["editor.tool.lasso"])
        XCTAssertEqual(XCTWaiter.wait(for: [toolGone], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["editor.addPage"].isEnabled)
        app.buttons["editor.readOnly"].tap()
        XCTAssertTrue(app.buttons["editor.tool.lasso"].waitForExistence(timeout: 5))
        app.buttons["editor.tool.stickyNote"].tap()
        XCTAssertTrue(app.staticTexts["Tap the page to place a sticky note"].waitForExistence(timeout: 5))
        let canvas = app.scrollViews["editor.canvas"]
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5)).tap()
        let placementGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["Tap the page to place a sticky note"])
        XCTAssertEqual(XCTWaiter.wait(for: [placementGone], timeout: 5), .completed)
        XCTAssertTrue(app.buttons["editor.tool.lasso"].isSelected)
        app.buttons["workspace.library"].tap()
        XCTAssertTrue(app.segmentedControls["library.layout"].waitForExistence(timeout: 5))
        app.segmentedControls["library.layout"].buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.buttons["Integration notebook"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.buttons["Integration notebook"].firstMatch.frame.width, app.frame.width * 0.4)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Redesigned library list"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
