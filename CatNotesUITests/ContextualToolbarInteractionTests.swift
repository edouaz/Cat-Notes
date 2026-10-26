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
        XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
        XCTAssertTrue(app.scrollViews["editor.canvas"].waitForExistence(timeout: 10))

        let undo = app.buttons["Annuler"]
        let undoFrame = undo.frame
        let tools = app.scrollViews.containing(.button, identifier: "Stylo").firstMatch
        if tools.exists {
            tools.swipeLeft()
            XCTAssertEqual(undo.frame, undoFrame, "L’historique reste épinglé pendant le défilement des outils")
            tools.swipeRight()
        } else {
            XCTAssertEqual(app.buttons["Stylo"].frame.midY, app.buttons["Couleur favorite 1"].frame.midY, accuracy: 2,
                           "Les instruments et leurs réglages partagent une seule rangée sur iPad")
        }
        XCTAssertTrue(undo.isHittable)

        app.buttons["Gomme"].tap()
        let quickMode = app.buttons["instrument.eraser.quickMode"]
        XCTAssertTrue(quickMode.waitForExistence(timeout: 5)); quickMode.tap()
        app.buttons["Pixel"].tap()
        let size = app.sliders["Taille de la gomme rapide"]
        XCTAssertTrue(size.isHittable); size.adjust(toNormalizedSliderPosition: 0.6)
        let chosenSize = size.value as? String
        app.buttons["Gomme"].tap()
        XCTAssertTrue(app.navigationBars["Instrument"].waitForExistence(timeout: 5))
        let detailedSize = app.sliders["Taille de la gomme"]
        XCTAssertEqual(detailedSize.value as? String, chosenSize, "Les accès rapide et détaillé partagent le même réglage")
        app.buttons["Terminé"].tap()

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
        attachment.name = "Outils contextuels après relancement"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
