import XCTest

@MainActor
final class CustomEditorExperienceTests: XCTestCase {
    private let app = XCUIApplication()
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        // An old install may still have the native-palette preference enabled.
        app.launchArguments = ["-nativeTools", "YES", "-inkTool", "pen", "-fingerDrawing", "NO",
                               "-showUndo", "YES", "-showInkColor", "YES", "-showInkWidth", "YES",
                               "-openNotebooks", "()", "-activeNotebook", ""]
        app.launch()
        if app.buttons["workspace.library"].waitForExistence(timeout: 3) { app.buttons["workspace.library"].tap() }
        XCTAssertTrue(app.buttons["library.create"].waitForExistence(timeout: 10)); app.buttons["library.create"].tap()
        XCTAssertTrue(app.buttons["editor.pages"].waitForExistence(timeout: 10))
        if app.buttons["editor.ruler"].isSelected { app.buttons["editor.ruler"].tap() }
    }
    override func tearDownWithError() throws {
        if let testRun, testRun.failureCount > 0 {
            let tree = XCTAttachment(string: app.debugDescription); tree.name = "Custom editor hierarchy"; tree.lifetime = .keepAlways; add(tree)
            capture("Custom editor — failure")
        }
        app.terminate()
    }
    func testCustomToolbarPreviewAndWidthSettingWithoutNativePalette() {
        let pen = app.buttons["Pen"], favorite = app.buttons["Favorite color 1"]
        XCTAssertTrue(pen.isHittable); XCTAssertTrue(favorite.isHittable)
        XCTAssertEqual(pen.frame.midY, favorite.frame.midY, accuracy: 2)
        capture("Custom editor — single-row toolbar")
        app.buttons["Instrument settings"].tap()
        XCTAssertTrue(app.navigationBars["Instrument"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "instrument.inkPreview").firstMatch.waitForExistence(timeout: 5))
        let width = app.sliders["Stroke width"]
        if !width.isHittable { app.scrollViews["instrument.options.scroll"].swipeUp() }
        XCTAssertTrue(width.isHittable)
        width.adjust(toNormalizedSliderPosition: 0.75)
        capture("Pen — actual preview and changed width")
        app.buttons["Done"].tap()
        app.buttons["editor.actions"].tap(); app.buttons["Customize tools"].tap()
        XCTAssertTrue(app.navigationBars["Writing"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Apple palette"].exists)
        XCTAssertFalse(app.segmentedControls["Tools"].exists)
        capture("Customization — Apple palette removed")
    }
    func testDoubleTapFromManualZoomFitsWidthThenHeight() {
        let canvas = app.scrollViews["editor.canvas"]
        let frame = canvas.frame
        let full = max(0.1, min(4, (frame.width - 32) / 794, (frame.height - 32) / 1123))
        let widthPercent = Int((((frame.width - 32) / 794) / full * 100).rounded())
        let heightPercent = Int((((frame.height - 32) / 1123) / full * 100).rounded())
        canvas.pinch(withScale: 2.4, velocity: 2)
        canvas.doubleTap()
        expectZoom(canvas, percent: widthPercent)
        capture("Double tap — fit width after free zoom")
        canvas.doubleTap()
        expectZoom(canvas, percent: heightPercent)
        capture("Double tap — fit height")
    }
    private func expectZoom(_ canvas: XCUIElement, percent: Int) {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let current = (canvas.value as? String ?? "").split(separator: " ").compactMap { Int($0) }.first ?? -1
            return abs(current - percent) <= 2
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
