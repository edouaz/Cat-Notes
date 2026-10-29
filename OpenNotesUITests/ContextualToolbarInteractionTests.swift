import XCTest

@MainActor
final class ContextualToolbarInteractionTests: XCTestCase {
    func testQuickToolSettingsPersistAndUndoStaysOutsideScrollingTools() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-nativeTools", "NO", "-inkTool", "pen", "-showUndo", "YES"]
        app.launch()
        defer { app.terminate() }
        if app.buttons["workspace.library"].waitForExistence(timeout: 5) { app.buttons["workspace.library"].tap() }
        let create = app.buttons["library.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap(); XCTAssertTrue(app.buttons["library.new.confirm"].waitForExistence(timeout: 5)); app.buttons["library.new.confirm"].tap()
        XCTAssertTrue(app.scrollViews["editor.canvas"].waitForExistence(timeout: 10))

        let undo = app.buttons["Undo"]
        let undoFrame = undo.frame
        let tools = app.scrollViews.containing(.button, identifier: "Pen").firstMatch
        if tools.exists {
            tools.swipeLeft()
            XCTAssertEqual(undo.frame, undoFrame, "History stays pinned while scrolling tools")
            tools.swipeRight()
        } else {
            XCTAssertEqual(app.buttons["Pen"].frame.midY, app.buttons["Favorite color 1"].frame.midY, accuracy: 2,
                           "Instruments and their settings share a single row on iPad")
        }
        XCTAssertTrue(undo.isHittable)

        app.buttons["Eraser"].tap()
        let quickMode = app.buttons["instrument.eraser.quickMode"]
        XCTAssertTrue(quickMode.waitForExistence(timeout: 5)); quickMode.tap()
        app.buttons["Pixel"].tap()
        let size = app.sliders["Quick eraser size"]
        XCTAssertTrue(size.isHittable); size.adjust(toNormalizedSliderPosition: 0.6)
        let chosenSize = size.value as? String
        app.buttons["Eraser"].tap()
        XCTAssertTrue(app.navigationBars["Instrument"].waitForExistence(timeout: 5))
        let detailedSize = app.sliders["Eraser size"]
        XCTAssertEqual(detailedSize.value as? String, chosenSize, "Quick and detailed controls share the same setting")
        app.buttons["Done"].tap()

        app.buttons["Lasso"].tap()
        let quickShape = app.buttons["instrument.lasso.quickShape"]
        XCTAssertTrue(quickShape.waitForExistence(timeout: 5)); quickShape.tap()
        app.buttons["Rectangle"].tap()
        let chosenShape = quickShape.value as? String ?? quickShape.label
        app.terminate(); app.launch()
        XCTAssertTrue(app.scrollViews["editor.canvas"].waitForExistence(timeout: 10))
        if !app.buttons["Lasso"].isSelected { app.buttons["Lasso"].tap() }
        XCTAssertTrue(quickShape.waitForExistence(timeout: 5))
        XCTAssertEqual(quickShape.value as? String ?? quickShape.label, chosenShape)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Contextual tools after relaunch"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
