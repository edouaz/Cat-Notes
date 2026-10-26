import XCTest
import UIKit

@MainActor
final class CanvasInteractionUITests: XCTestCase {
    private let app = XCUIApplication()
    private var canvas: XCUIElement { app.descendants(matching: .any).matching(identifier: "editor.canvas").firstMatch }
    private var insertedImage: XCUIElement { app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'image.' AND label == 'Image'")).firstMatch }

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-nativeTools", "NO", "-inkTool", "pen", "-fingerDrawing", "NO"]
        app.launch()
        if app.buttons["workspace.library"].waitForExistence(timeout: 5) { app.buttons["workspace.library"].tap() }
        XCTAssertTrue(app.buttons["library.create"].waitForExistence(timeout: 10))
        app.buttons["library.create"].tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
    }
    override func tearDownWithError() throws {
        if let testRun, testRun.failureCount > 0 {
            screenshot("Canvas — failure")
            let tree = XCTAttachment(string: app.debugDescription); tree.name = "Canvas — hierarchy"; tree.lifetime = .keepAlways; add(tree)
        }
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }
    func testCapturedImageFreeTapReselectFingerDragAndDelete() {
        insertCapture()
        screenshot("Inserted image — outline and handles")
        deselectImage()
        XCTAssertFalse(app.buttons["editor.mode.done"].exists)
        insertedImage.tap()
        XCTAssertEqual(insertedImage.value as? String, "Selected")
        moveImage()
        screenshot("Image — finger drag after reselection")
        let frame = insertedImage.frame
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.maxX - 22, dy: frame.minY - 28)).tap()
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: insertedImage)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 5), .completed)
        screenshot("Image — deletion from corner control")
    }
    func testImageHandlesAfterPinchAndRotation() {
        insertCapture(); deselectImage()
        canvas.pinch(withScale: 2, velocity: 1)
        let zoomed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let value = (self.canvas.value as? String ?? "").split(separator: " ").compactMap { Int($0) }.first ?? 0
            return value > 120
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [zoomed], timeout: 5), .completed)
        insertedImage.tap()
        let before = insertedImage.frame
        let right = point(CGPoint(x: before.maxX, y: before.midY))
        right.press(forDuration: 0.05, thenDragTo: right.withOffset(CGVector(dx: 25, dy: 0)))
        let resized = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.insertedImage.frame.width > before.width + 10 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [resized], timeout: 5), .completed)
        XCTAssertEqual(insertedImage.frame.height, before.height, accuracy: 2)
        let side = insertedImage.frame
        let corner = point(CGPoint(x: side.minX, y: side.maxY))
        corner.press(forDuration: 0.05, thenDragTo: corner.withOffset(CGVector(dx: -15, dy: 15)))
        XCTAssertEqual(insertedImage.frame.width / insertedImage.frame.height, side.width / side.height, accuracy: 0.02)
        screenshot("Image — side and corner handles while zoomed")
        XCUIDevice.shared.orientation = .landscapeLeft
        canvas.doubleTap()
        insertedImage.tap()
        XCTAssertEqual(insertedImage.value as? String, "Selected")
        moveImage()
        screenshot("Image — selection and dragging after rotation")
    }
    private func point(_ point: CGPoint) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y))
    }
    private func insertCapture() {
        app.buttons["editor.insert"].tap()
        let capture = app.buttons["Capture entire page"]
        for _ in 0..<5 where !capture.isHittable { app.swipeUp() }
        XCTAssertTrue(capture.isHittable); capture.tap()
        XCTAssertTrue(app.buttons["capture.insert"].waitForExistence(timeout: 10))
        app.buttons["capture.insert"].tap()
        XCTAssertTrue(insertedImage.waitForExistence(timeout: 10))
        XCTAssertEqual(insertedImage.value as? String, "Selected")
    }
    private func deselectImage() {
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.12)).tap()
        let deselected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", "Selected"), object: insertedImage)
        XCTAssertEqual(XCTWaiter.wait(for: [deselected], timeout: 5), .completed)
    }
    private func moveImage() {
        let before = insertedImage.frame
        let start = insertedImage.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 35, dy: 25)))
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in abs(self.insertedImage.frame.minX - before.minX) > 15 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed)
    }
    func testStickyNoteDirectCreationCollapseUnfoldAndReopenEditorKeepsText() {
        let direct = app.buttons["Sticky note"]
        if direct.isHittable { direct.tap() }
        else { app.buttons["editor.insert"].tap(); app.buttons["editor.sticky.add"].tap() }
        let text = app.textViews["Sticky note text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5)); text.tap(); text.typeText("Text preserved after collapse")
        app.buttons["Save"].tap()
        let note = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sticky note: Text preserved'")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10))
        let expanded = note.frame
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: expanded.maxX - 22, dy: expanded.minY + 22)).tap()
        let collapsed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'Collapsed'"), object: note)
        XCTAssertEqual(XCTWaiter.wait(for: [collapsed], timeout: 5), .completed)
        screenshot("Sticky note — collapse without text loss")
        note.tap()
        let unfolded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'Expanded'"), object: note)
        XCTAssertEqual(XCTWaiter.wait(for: [unfolded], timeout: 5), .completed)
        note.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.55)).tap()
        XCTAssertTrue(text.waitForExistence(timeout: 5)); XCTAssertEqual(text.value as? String, "Text preserved after collapse")
        screenshot("Sticky note — text restored in editor")
        app.navigationBars["Sticky note"].buttons["Cancel"].tap()
    }
    private func screenshot(_ name: String) {
        let evidence = XCTAttachment(screenshot: app.screenshot()); evidence.name = name; evidence.lifetime = .keepAlways; add(evidence)
    }
}
