import XCTest

@MainActor
final class ToolInteractionTests: XCTestCase {
    func testDirectToolsAnchoredOptionsEraserSizeAndIntegratedPages() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-nativeTools", "NO", "-inkTool", "pen"]
        app.launch()
        defer { app.terminate() }
        if app.buttons["workspace.library"].waitForExistence(timeout: 5) { app.buttons["workspace.library"].tap() }
        XCTAssertTrue(app.buttons["library.create"].waitForExistence(timeout: 10))
        app.buttons["library.create"].tap()
        XCTAssertTrue(app.scrollViews["editor.canvas"].waitForExistence(timeout: 10))
        for id in ["editor.pages", "editor.search", "editor.insert", "editor.share", "editor.image", "editor.sticky"] {
            XCTAssertTrue(app.buttons[id].isHittable, id)
        }
        app.buttons["Pen"].tap()
        XCTAssertTrue(app.navigationBars["Instrument"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["Stabilization"].exists)
        screenshot(app, "Options below the active pen")
        app.buttons["Done"].tap()
        app.buttons["Eraser"].tap()
        XCTAssertFalse(app.navigationBars["Instrument"].exists, "First tap selects; second opens options")
        app.buttons["Eraser"].tap()
        XCTAssertTrue(app.navigationBars["Instrument"].waitForExistence(timeout: 5))
        let size = app.sliders["Eraser size"]
        XCTAssertTrue(size.isHittable)
        size.adjust(toNormalizedSliderPosition: 0.42)
        let chosen = size.value as? String
        for mode in ["Whole stroke", "Pixel", "Intelligent"] {
            app.buttons["instrument.eraser.mode"].tap()
            app.buttons[mode].tap()
            XCTAssertEqual(size.value as? String, chosen)
        }
        screenshot(app, "Pixel eraser and preserved size")
        app.buttons["Done"].tap()
        let canvas = app.scrollViews["editor.canvas"]
        let before = canvas.exists ? canvas.frame : app.otherElements["editor.canvas"].frame
        app.buttons["editor.pages"].tap()
        XCTAssertTrue(app.buttons["editor.pages.close"].waitForExistence(timeout: 5))
        let after = canvas.exists ? canvas.frame : app.otherElements["editor.canvas"].frame
        if app.frame.width >= 700 {
            XCTAssertLessThan(after.width, before.width)
            XCTAssertGreaterThan(after.width, 200)
        }
        screenshot(app, "Previews in the integrated panel")
        app.buttons["editor.pages.close"].tap()
        XCTAssertFalse(app.buttons["editor.pages.close"].exists)
    }
    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
