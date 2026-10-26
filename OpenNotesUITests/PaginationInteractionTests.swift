import XCTest
import UIKit

@MainActor
final class PaginationInteractionTests: XCTestCase {
    private let app = XCUIApplication()
    private var notebookID = ""
    private var canvas: XCUIElement { app.descendants(matching: .any).matching(identifier: "editor.canvas").firstMatch }
    private var position: XCUIElement { app.buttons["editor.pages"] }

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-nativeTools", "NO", "-fingerDrawing", "NO", "-verticalPaging", "NO", "-inkTool", "pen", "-openNotebooks", "()", "-activeNotebook", ""]
        app.launch()
        let library = app.buttons["workspace.library"]
        if library.waitForExistence(timeout: 5) { library.tap() }
        XCTAssertTrue(app.buttons["library.create"].waitForExistence(timeout: 10))
        let notebooks = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "library.note."))
        let previous = Set(notebooks.allElementsBoundByIndex.map(\.identifier))
        app.buttons["library.create"].tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        app.buttons["workspace.library"].tap()
        let created = notebooks.matching(NSPredicate(format: "NOT (identifier IN %@)", argumentArray: [Array(previous)])).firstMatch
        XCTAssertTrue(created.waitForExistence(timeout: 10))
        notebookID = created.identifier
        created.tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        app.launchArguments.removeLast(4)
    }

    override func tearDownWithError() throws {
        if let testRun, testRun.failureCount > 0 {
            screenshot("Pagination failure")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Pagination failure hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testTwentyRealSwipeRoundTripsBoundariesZoomAndReopen() {
        for page in 2...3 {
            app.buttons["editor.insert"].tap()
            XCTAssertTrue(app.buttons["editor.addPage"].waitForExistence(timeout: 5))
            app.buttons["editor.addPage"].tap()
            waitForPage(page, total: page)
        }
        swipe(1, to: 2); swipe(1, to: 1)
        screenshot("Pagination before repetition, three pages")
        for cycle in 0..<20 {
            swipe(-1, to: 2)
            if cycle.isMultiple(of: 5) { swipe(-1, to: 3); swipe(1, to: 2) }
            swipe(1, to: 1)
        }
        screenshot("Pagination after twenty real next previous round trips")
        drag(from: 0.5, to: 0.55)
        waitForPage(1)
        swipe(-1, to: 2)
        drag(from: 0.5, to: 0.45)
        waitForPage(2)
        swipe(-1, to: 3)
        drag(from: 0.5, to: 0.45)
        waitForPage(3)
        swipe(1, to: 2)
        canvas.pinch(withScale: 2, velocity: 1)
        waitForZoom(above: 120)
        drag(from: 0.75, to: 0.25)
        waitForPage(2)
        screenshot("Zoomed page keeps canvas pan")
        app.buttons["workspace.library"].tap()
        XCTAssertTrue(app.buttons[notebookID].waitForExistence(timeout: 10))
        app.buttons[notebookID].tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        waitForPage(2)
        waitForZoom(above: 120)
        drag(from: 0.75, to: 0.25)
        waitForPage(2)
        app.terminate(); app.launch()
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        waitForPage(2)
        waitForZoom(above: 120)
        drag(from: 0.75, to: 0.25)
        waitForPage(2)
        canvas.doubleTap() // Width from a manually zoomed position.
        canvas.doubleTap() // Height is the full-page fit for this portrait notebook.
        waitForZoom(above: 99, below: 102)
        swipe(-1, to: 3)
        swipe(1, to: 2)
        XCUIDevice.shared.orientation = .landscapeLeft
        swipe(1, to: 1)
        screenshot("Pagination after reopening, fit and landscape")
        let evidence = XCTAttachment(string: "20 real next/previous round trips, 4 visits to page 3, short drags at both notebook boundaries, cancellation, zoom/canvas pan, notebook close/reopen with the same session, app relaunch, fit and landscape. Simulator OS: \(UIDevice.current.systemVersion).")
        evidence.name = "Real gesture repetition"; evidence.lifetime = .keepAlways; add(evidence)
    }

    func testZoomPanAndReopenPreserveTheMagnification() {
        app.buttons["editor.insert"].tap(); app.buttons["editor.addPage"].tap()
        waitForPage(2, total: 2)
        canvas.pinch(withScale: 2.0, velocity: 1)
        waitForZoom(above: 120)
        screenshot("Pinch — actual zoom above 120 percent")
        drag(from: 0.75, to: 0.25); waitForPage(2, total: 2)
        app.buttons["workspace.library"].tap()
        XCTAssertTrue(app.buttons[notebookID].waitForExistence(timeout: 10)); app.buttons[notebookID].tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 10)); waitForZoom(above: 120)
        drag(from: 0.75, to: 0.25); waitForPage(2, total: 2)
        canvas.pinch(withScale: 0.4, velocity: -1); waitForZoom(above: 99, below: 102)
        screenshot("Reverse pinch — page fitted after reopening")
        swipe(1, to: 1, total: 2)
    }
    private func waitForZoom(above minimum: Int, below maximum: Int = 1000) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let digits = (self.canvas.value as? String ?? "").split(separator: " ").compactMap { Int($0) }
            return digits.first.map { $0 > minimum && $0 < maximum } ?? false
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed, "Actual zoom: \(canvas.value ?? "nil")")
    }
    private func swipe(_ direction: CGFloat, to page: Int, total: Int = 3) {
        drag(from: direction > 0 ? 0.22 : 0.78, to: direction > 0 ? 0.78 : 0.22)
        waitForPage(page, total: total)
    }

    private func drag(from start: CGFloat, to end: CGFloat) {
        XCTAssertTrue(canvas.exists)
        let beginning = canvas.coordinate(withNormalizedOffset: CGVector(dx: start, dy: 0.5))
        let ending = canvas.coordinate(withNormalizedOffset: CGVector(dx: end, dy: 0.5))
        beginning.press(forDuration: 0.05, thenDragTo: ending, withVelocity: .slow, thenHoldForDuration: 0.2)
    }

    private func waitForPage(_ page: Int, total: Int = 3) {
        let expected = "Page \(page) of \(total)"
        let installed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: position)
        XCTAssertEqual(XCTWaiter.wait(for: [installed], timeout: 10), .completed, expected)
    }

    private func screenshot(_ name: String) {
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = name; evidence.lifetime = .keepAlways; add(evidence)
    }
}
