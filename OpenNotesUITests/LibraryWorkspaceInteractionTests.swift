import XCTest
import UIKit

@MainActor
final class LibraryWorkspaceInteractionTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-nativeTools", "NO", "-inkTool", "pen",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        returnToLibrary()
        let documents = app.buttons["Documents"].firstMatch
        if documents.exists { documents.tap() }
    }

    override func tearDownWithError() throws {
        if let testRun, testRun.failureCount > 0 {
            screenshot("Library and tabs on failure")
            let attachment = XCTAttachment(string: app.debugDescription)
            attachment.name = "Hierarchy on failure"; attachment.lifetime = .keepAlways; add(attachment)
        }
        app.terminate()
    }

    func testTabMenuRenamePersistsAndClosingPreservesNotebooks() throws {
        let token = UUID().uuidString.prefix(8)
        let firstTitle = "Voyage \(token)"
        let secondTitle = "My ideas for the coming weeks \(token)"
        let first = try createNotebook()
        renameFromTab(first, to: firstTitle)
        assertTabLayout(id: first, title: firstTitle)
        screenshot("Tab renamed from the arrow and separate close control")

        returnToLibrary()
        let firstCard = app.buttons["library.note.\(first)"]
        reveal(firstCard)
        XCTAssertEqual(firstCard.label, firstTitle)
        screenshot("Notebook title preserved in library")
        firstCard.tap()
        XCTAssertTrue(app.buttons["editor.pages"].waitForExistence(timeout: 10))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["workspace.options.\(first)"].waitForExistence(timeout: 10))
        assertTabLayout(id: first, title: firstTitle)
        screenshot("Title and active tab after relaunch")

        returnToLibrary()
        let second = try createNotebook()
        renameFromTab(second, to: secondTitle)
        assertTabLayout(id: second, title: secondTitle)
        screenshot("Stable tabs with a long title")

        app.buttons["Close \(secondTitle)"].tap()
        waitUntilGone(app.buttons["workspace.options.\(second)"])
        XCTAssertTrue(app.buttons[firstTitle].waitForExistence(timeout: 5))
        assertTabLayout(id: first, title: firstTitle)
        app.buttons["Close \(firstTitle)"].tap()
        waitUntilGone(app.buttons["workspace.options.\(first)"])
        returnToLibrary()
        for (id, title) in [(first, firstTitle), (second, secondTitle)] {
            let card = app.buttons["library.note.\(id)"]
            reveal(card)
            XCTAssertEqual(card.label, title, "Closing a tab must preserve its notebook")
        }
        screenshot("Notebooks preserved after closing their tabs")
    }

    private var options: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workspace.options."))
    }

    private func createNotebook() throws -> String {
        let create = app.buttons["library.create"]
        reveal(create, towardTop: true); create.tap()
        XCTAssertTrue(app.buttons["editor.pages"].waitForExistence(timeout: 10))
        let appended = try XCTUnwrap(options.allElementsBoundByIndex.last,
                                    "The tab flow requires an iPad at regular width")
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: appended)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed)
        return String(appended.identifier.dropFirst("workspace.options.".count))
    }

    private func renameFromTab(_ id: String, to title: String) {
        let arrow = app.buttons["workspace.options.\(id)"]
        XCTAssertTrue(arrow.isHittable)
        XCTAssertGreaterThanOrEqual(arrow.frame.width, 44)
        XCTAssertGreaterThanOrEqual(arrow.frame.height, 44)
        arrow.tap()
        let rename = app.buttons["Rename"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5)); rename.tap()
        let alert = app.alerts["Rename notebook"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let field = alert.textFields["Title"]
        let old = field.value as? String ?? ""
        field.tap(); field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + title)
        alert.buttons["Save"].tap()
        let renamed = app.buttons[title]
        XCTAssertTrue(renamed.waitForExistence(timeout: 5))
        XCTAssertEqual(arrow.label, "Options for \(title)")
    }

    private func assertTabLayout(id: String, title: String) {
        let tab = app.buttons[title], arrow = app.buttons["workspace.options.\(id)"], close = app.buttons["Close \(title)"]
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true AND isHittable == true"), object: tab)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        let strip = app.scrollViews.containing(.button, identifier: arrow.identifier).firstMatch
        XCTAssertTrue(strip.exists)
        XCTAssertTrue(strip.frame.contains(tab.frame))
        XCTAssertTrue(strip.frame.contains(arrow.frame))
        XCTAssertTrue(strip.frame.contains(close.frame))
        XCTAssertGreaterThanOrEqual(close.frame.width, 44)
        XCTAssertGreaterThanOrEqual(close.frame.height, 44)
        XCTAssertLessThanOrEqual(tab.frame.maxX, arrow.frame.minX + 1)
        XCTAssertLessThanOrEqual(arrow.frame.maxX, close.frame.minX + 1)
        let width = close.frame.maxX - tab.frame.minX
        XCTAssertEqual(width, min(240, strip.frame.width - 8), accuracy: 2,
                       "Tab width stays stable as other documents open and close")
    }

    private func returnToLibrary() {
        let library = app.buttons["workspace.library"]
        if library.waitForExistence(timeout: 3) { library.tap() }
        XCTAssertTrue(app.buttons["library.create"].waitForExistence(timeout: 10))
    }

    private func waitUntilGone(_ element: XCUIElement) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
    }

    private func reveal(_ element: XCUIElement, towardTop: Bool = false) {
        let scroll = app.scrollViews.containing(.button, identifier: "library.create").firstMatch
        for _ in 0..<12 {
            if element.exists, element.isHittable, app.frame.contains(element.frame) { return }
            guard scroll.exists else { break }
            let up = element.exists ? element.frame.midY < scroll.frame.midY : towardTop
            if up { scroll.swipeDown() } else { scroll.swipeUp() }
        }
        XCTAssertTrue(element.isHittable, "The notebook or control must be reachable by scrolling")
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
