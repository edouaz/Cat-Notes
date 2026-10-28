import XCTest

@MainActor
final class NativeInkInteractionUITests: XCTestCase {
    func testFingerInkUndoRedoAndReopen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-fingerDrawing", "YES", "-inkTool", "pen", "-openNotebooks", "()", "-activeNotebook", ""]
        app.launch()
        defer { app.terminate() }
        if app.buttons["workspace.library"].waitForExistence(timeout: 3) { app.buttons["workspace.library"].tap() }
        XCTAssertTrue(app.buttons["library.create"].waitForExistence(timeout: 10))
        app.buttons["library.create"].tap()
        let canvas = app.scrollViews["editor.canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        let tab = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workspace.tab.")).firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        let notebookID = String(tab.identifier.dropFirst("workspace.tab.".count))

        let undo = app.buttons["Undo"], redo = app.buttons["Redo"]
        XCTAssertFalse(undo.isEnabled)
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.4))
        start.press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.6)))
        waitEnabled(undo)
        capture(app, "Native UIView ink — actual finger stroke")
        undo.tap(); waitEnabled(redo)
        XCTAssertFalse(undo.isEnabled)
        redo.tap(); waitEnabled(undo)
        XCTAssertFalse(redo.isEnabled)
        capture(app, "Native UIView ink — redo restored")

        app.buttons["editor.toolOptions"].tap()
        let options = app.scrollViews["instrument.options.scroll"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        let pattern = app.buttons["instrument.pattern"]
        for _ in 0..<4 where !pattern.isHittable {
            // Popover scroll views can report an empty XCTest visible frame; use the displayed bounds.
            let frame = options.frame
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.maxY - 30))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.minY + 30))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(pattern.isHittable, "Native patterns must be reachable from the active toolbar")
        capture(app, "Native pen options — pattern and stabilization")
        app.buttons["Done"].tap()

        app.buttons["workspace.library"].tap()
        XCTAssertTrue(app.buttons["library.create"].waitForExistence(timeout: 10))
        app.terminate(); app.launch()
        let notebook = app.buttons["library.note." + notebookID]
        XCTAssertTrue(notebook.waitForExistence(timeout: 10)); notebook.tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        XCTAssertFalse(undo.isEnabled, "Reopening resets editing history")
        capture(app, "Native ink — persisted page after process relaunch")
    }
    private func waitEnabled(_ button: XCUIElement) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
