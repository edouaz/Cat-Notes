import XCTest
import UIKit

@MainActor
final class ToolPersonalizationTests: XCTestCase {
    private let app = XCUIApplication()
    private var favorites: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Favorite color "))
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-nativeTools", "NO", "-inkTool", "pen",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        let isolatedTabs = name.contains("testFingerPenStroke")
        if isolatedTabs { app.launchArguments += ["-openNotebooks", "()", "-activeNotebook", ""] }
        app.launch()
        if app.buttons["workspace.library"].waitForExistence(timeout: 5) { app.buttons["workspace.library"].tap() }
        XCTAssertTrue(app.buttons["library.create"].waitForExistence(timeout: 10))
        app.buttons["library.create"].tap()
        XCTAssertTrue(app.buttons["editor.pages"].waitForExistence(timeout: 10))
        if isolatedTabs { app.launchArguments.removeLast(4) }
    }

    override func tearDownWithError() throws {
        if let testRun, testRun.failureCount > 0 {
            screenshot("Customization — failure")
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "Customization — hierarchy"; tree.lifetime = .keepAlways; add(tree)
        }
        app.terminate()
    }

    func testToolVisibilityAndSeparateFavoritesPersistAfterRelaunch() throws {
        openCustomization()
        let labels = ["Pen", "Pencil", "Highlighter", "Lasso", "Favorite colors on iPad"]
        var initialVisibility: [String: Bool] = [:]
        for label in labels {
            let control = toggle(label)
            reveal(control)
            initialVisibility[label] = control.value as? String == "1"
        }
        setToggle("Pen", true); setToggle("Highlighter", true)
        setToggle("Lasso", true); setToggle("Pencil", false)
        setToggle("Favorite colors on iPad", true)
        closeCustomization()
        XCTAssertFalse(app.buttons["Pencil"].exists)
        XCTAssertTrue(app.buttons["Lasso"].exists)
        screenshot("Pencil hidden before customization")

        openCustomization()
        setToggle("Pencil", true); setToggle("Lasso", false)
        closeCustomization()
        assertPersonalizedToolbar()
        screenshot("Pencil visible and lasso hidden in the toolbar")

        selectTool("Pen")
        let penBefore = favoriteValues()
        selectTool("Highlighter")
        let markerBefore = favoriteValues()
        guard penBefore.count < 64, markerBefore.count < 64 else {
            restoreVisibility(initialVisibility)
            throw XCTSkip("Adding requires a free slot among each tool’s 64 favorites; no existing favorite is deleted.")
        }

        selectTool("Pen")
        let penAfter = try addFavoriteOfSelectedTool()
        XCTAssertEqual(Array(penAfter.dropLast()), penBefore)
        let selectedFavorite = app.buttons["Favorite color \(penAfter.count)"]
        revealFavorite(selectedFavorite)
        XCTAssertTrue(selectedFavorite.isSelected)
        selectedFavorite.tap()
        XCTAssertTrue(app.staticTexts["Edit favorite"].waitForExistence(timeout: 5),
                      "Tapping the active color again must open its editor")
        screenshot("Tap an active favorite again to edit it")
        let title = app.staticTexts["Edit favorite"].frame
        let cancel = try XCTUnwrap(app.buttons.matching(identifier: "Cancel").allElementsBoundByIndex.first {
            $0.isHittable && $0.frame.minY > title.maxY
        })
        cancel.tap()
        waitUntilGone(app.staticTexts["Edit favorite"])
        XCTAssertEqual(favoriteValues(), penAfter, "Canceling the edit must preserve the color and its order")

        selectTool("Highlighter")
        XCTAssertEqual(favoriteValues(), markerBefore, "Adding a pen favorite must not change highlighter favorites")
        let markerAfter = try addFavoriteOfSelectedTool()
        XCTAssertEqual(Array(markerAfter.dropLast()), markerBefore)
        screenshot("Highlighter favorites after independent addition")
        selectTool("Pen")
        XCTAssertEqual(favoriteValues(), penAfter, "Adding a highlighter favorite must not change pen favorites")
        screenshot("Pen favorites preserved after switching tools")

        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["editor.pages"].waitForExistence(timeout: 10))
        assertPersonalizedToolbar()
        selectTool("Pen"); XCTAssertEqual(favoriteValues(), penAfter)
        selectTool("Highlighter"); XCTAssertEqual(favoriteValues(), markerAfter)
        screenshot("Per-tool visibility and favorites after relaunch")
        restoreVisibility(initialVisibility)

        let scope = XCTAttachment(string: "Touch flow: pencil hidden then shown, lasso hidden, adding and selecting one favorite per tool, independent lists and preservation after relaunch. Tapping the active favorite again opens Edit; cancel preserves the list. Reordering and choosing a new color in the system panel are not exercised. Initial visibility is restored; both added favorites and the created notebook are kept.")
        scope.name = "Customization flow scope"; scope.lifetime = .keepAlways; add(scope)
    }

    func testFingerPenStrokeDisappearsWithOneUndoAndReturnsWithRedo() throws {
        app.terminate()
        app.launchArguments += ["-fingerDrawing", "YES", "-showUndo", "YES", "-showInkColor", "YES", "-showInkWidth", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["editor.pages"].waitForExistence(timeout: 10))
        openCustomization(); setToggle("Pen", true); closeCustomization()
        selectTool("Pen")
        let dark = try XCTUnwrap(favorites.allElementsBoundByIndex.first { color in
            guard let hex = color.value as? String, hex.count == 7,
                  let rgb = UInt32(hex.dropFirst(), radix: 16) else { return false }
            return (rgb >> 16) < 90 && ((rgb >> 8) & 255) < 90 && (rgb & 255) < 90
        }, "The pixel check requires a dark favorite distinguishable from the grid")
        revealFavorite(dark)
        if !dark.isSelected { dark.tap() }
        let thick = app.buttons["Width 6 points"]
        XCTAssertTrue(thick.isHittable); thick.tap()

        for (index, style) in ["Ballpoint", "Fountain"].enumerated() {
            setPenStyle(style)
            let canvas = app.descendants(matching: .any).matching(identifier: "editor.canvas").firstMatch
            XCTAssertTrue(canvas.waitForExistence(timeout: 5))
            let frame = canvas.frame
            let y: CGFloat = index == 0 ? 0.42 : 0.65
            let start = CGPoint(x: frame.minX + frame.width * 0.38, y: frame.minY + frame.height * y)
            let end = CGPoint(x: frame.minX + frame.width * 0.62, y: frame.minY + frame.height * (y + 0.06))
            let roi = CGRect(x: start.x, y: start.y, width: end.x - start.x, height: end.y - start.y)
                .insetBy(dx: -20, dy: -20).intersection(frame)
            let baseline = darkPixelCount(in: roi)
            XCTAssertGreaterThanOrEqual(baseline, 0)
            if index == 0 { XCTAssertFalse(app.buttons["Undo"].isEnabled, "A new notebook must start with empty history") }
            screenshot("\(style) — central area before the stroke")

            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: start.x - app.frame.minX, dy: start.y - app.frame.minY))
                .press(forDuration: 0.05,
                       thenDragTo: origin.withOffset(CGVector(dx: end.x - app.frame.minX, dy: end.y - app.frame.minY)),
                       withVelocity: .slow, thenHoldForDuration: 0.05)
            let undo = app.buttons["Undo"]
            let undoReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: undo)
            XCTAssertEqual(XCTWaiter.wait(for: [undoReady], timeout: 5), .completed)
            let drawn = waitForDarkPixels(in: roi, phase: "\(style): stroke added", matching: { $0 > baseline + 200 })
            screenshot("\(style) — stroke visible after finger drawing")

            undo.tap()
            let tolerance = max(12, (drawn - baseline) / 50)
            _ = waitForDarkPixels(in: roi, phase: "\(style): after ONE undo, expected background \(baseline)",
                                  matching: { $0 <= baseline + tolerance })
            screenshot("\(style) — one undo removes the stroke")
            if index == 0 { XCTAssertFalse(undo.isEnabled, "A single stroke must not leave a second profile undo step") }

            let redo = app.buttons["Redo"]
            let redoReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: redo)
            XCTAssertEqual(XCTWaiter.wait(for: [redoReady], timeout: 5), .completed)
            redo.tap()
            _ = waitForDarkPixels(in: roi, phase: "\(style): stroke restored",
                                  matching: { $0 >= baseline + (drawn - baseline) * 4 / 5 })
            screenshot("\(style) — redo restores the visible stroke")
        }
        setPenStyle("Ballpoint")
    }

    private func setPenStyle(_ style: String) {
        selectTool("Pen"); app.buttons["Pen"].tap()
        XCTAssertTrue(app.navigationBars["Instrument"].waitForExistence(timeout: 5))
        let styles = ["Ballpoint", "Fountain", "Brush"]
        let picker = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ OR label IN %@ OR value IN %@",
                                                     "Pen style", styles, styles)).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5)); reveal(picker); picker.tap()
        let option = app.buttons[style]
        XCTAssertTrue(option.waitForExistence(timeout: 5)); option.tap()
        app.navigationBars["Instrument"].buttons["Done"].tap()
        waitUntilGone(app.navigationBars["Instrument"])
    }

    private func waitForDarkPixels(in roi: CGRect, phase: String, matching condition: @escaping (Int) -> Bool) -> Int {
        var measured = -1
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            measured = self.darkPixelCount(in: roi)
            return measured >= 0 && condition(measured)
        }, object: nil)
        let result = XCTWaiter.wait(for: [changed], timeout: 5)
        let reading = XCTAttachment(string: "\(phase); ROI in points: \(roi); dark pixels: \(measured). Threshold: R, G and B < 90 and alpha > 200, excluding the light grid. No second Undo tap is attempted.")
        reading.name = phase; reading.lifetime = .keepAlways; add(reading)
        XCTAssertEqual(result, .completed, "\(phase); observed dark pixels: \(measured)")
        return measured
    }

    private func darkPixelCount(in roi: CGRect) -> Int {
        guard let full = app.screenshot().image.cgImage else { return -1 }
        let bounds = app.frame
        let sx = CGFloat(full.width) / bounds.width, sy = CGFloat(full.height) / bounds.height
        let pixels = CGRect(x: (roi.minX - bounds.minX) * sx, y: (roi.minY - bounds.minY) * sy,
                            width: roi.width * sx, height: roi.height * sy).integral
            .intersection(CGRect(x: 0, y: 0, width: full.width, height: full.height))
        guard let image = full.cropping(to: pixels), image.width > 0, image.height > 0 else { return -1 }
        var rgba = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let rendered = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard rendered else { return -1 }
        var count = 0
        for offset in stride(from: 0, to: rgba.count, by: 4) {
            if rgba[offset] < 90 && rgba[offset + 1] < 90 && rgba[offset + 2] < 90 && rgba[offset + 3] > 200 { count += 1 }
        }
        return count
    }

    private func openCustomization() {
        app.buttons["editor.actions"].tap()
        let customize = app.buttons["Customize tools"]
        XCTAssertTrue(customize.waitForExistence(timeout: 5))
        reveal(customize); customize.tap()
        XCTAssertTrue(app.navigationBars["Writing"].waitForExistence(timeout: 5))
    }

    private func closeCustomization() {
        app.navigationBars["Writing"].buttons["Done"].tap()
        waitUntilGone(app.navigationBars["Writing"])
    }

    private func restoreVisibility(_ initial: [String: Bool]) {
        openCustomization()
        for label in initial.keys.sorted() { setToggle(label, initial[label] == true) }
        closeCustomization()
    }

    private func toggle(_ title: String) -> XCUIElement {
        app.switches.matching(NSPredicate(format: "label == %@ OR label ENDSWITH %@", title, title)).firstMatch
    }

    private func setToggle(_ title: String, _ enabled: Bool) {
        let control = toggle(title)
        reveal(control)
        if (control.value as? String == "1") != enabled {
            let knob = control.switches.firstMatch
            if knob.exists { knob.tap() } else { control.tap() }
        }
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", enabled ? "1" : "0"), object: control)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
    }

    private func assertPersonalizedToolbar() {
        XCTAssertTrue(app.buttons["Pencil"].isHittable)
        XCTAssertFalse(app.buttons["Lasso"].exists)
        XCTAssertTrue(app.buttons["Add favorite color"].isHittable)
    }

    private func selectTool(_ title: String) {
        let tool = app.buttons[title]
        XCTAssertTrue(tool.isHittable)
        if !tool.isSelected { tool.tap() }
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: tool)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        XCTAssertFalse(app.navigationBars["Instrument"].exists)
    }

    private func favoriteValues() -> [String] {
        favorites.allElementsBoundByIndex.map { $0.value as? String ?? "" }
    }

    private func addFavoriteOfSelectedTool() throws -> [String] {
        let before = favoriteValues()
        var selectedHex: String?
        if !before.isEmpty {
            let index = min(2, before.count)
            let color = app.buttons["Favorite color \(index)"]
            revealFavorite(color)
            if !color.isSelected { color.tap() }
            XCTAssertTrue(color.isSelected)
            selectedHex = color.value as? String
        }
        app.buttons["Add favorite color"].tap()
        XCTAssertTrue(app.staticTexts["New favorite"].waitForExistence(timeout: 5))
        app.buttons["Add"].tap()
        waitUntilGone(app.staticTexts["New favorite"])
        let added = app.buttons["Favorite color \(before.count + 1)"]
        XCTAssertTrue(added.waitForExistence(timeout: 5))
        let hex = try XCTUnwrap(added.value as? String)
        XCTAssertTrue(hex.hasPrefix("#"))
        if let selectedHex { XCTAssertEqual(hex, selectedHex) }
        let after = favoriteValues()
        XCTAssertEqual(after, before + [hex])
        return after
    }

    private func revealFavorite(_ color: XCUIElement) {
        let strip = app.scrollViews.containing(.button, identifier: color.label).firstMatch
        for _ in 0..<12 {
            if color.isHittable { return }
            guard strip.exists else { break }
            if color.frame.midX < strip.frame.midX { strip.swipeRight() } else { strip.swipeLeft() }
        }
        XCTAssertTrue(color.isHittable, "Favorites must remain accessible through horizontal scrolling")
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<10 {
            if element.exists, element.isHittable { return }
            let containers = app.collectionViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex + app.scrollViews.allElementsBoundByIndex
            guard let scroll = containers.first(where: { $0.isHittable }) else { break }
            let above = element.exists && element.frame.midY < scroll.frame.midY
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: above ? 0.3 : 0.7))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: above ? 0.7 : 0.3))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(element.isHittable, "The setting must remain accessible in the panel")
    }

    private func waitUntilGone(_ element: XCUIElement) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
