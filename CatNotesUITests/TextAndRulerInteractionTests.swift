import XCTest

@MainActor
final class TextAndRulerInteractionTests: XCTestCase {
    func testFilledRectangleCanBeEditedDeletedAndRestoredWithUndo() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-nativeTools", "NO", "-showUndo", "YES", "-openNotebooks", "()", "-activeNotebook", ""]
        app.launch()
        defer { app.terminate() }
        if app.buttons["workspace.library"].waitForExistence(timeout: 3) { app.buttons["workspace.library"].tap() }
        XCTAssertTrue(app.buttons["library.create"].waitForExistence(timeout: 10))
        app.buttons["library.create"].tap()
        XCTAssertTrue(app.buttons["editor.insert"].waitForExistence(timeout: 10))
        app.buttons["editor.insert"].tap()
        app.buttons["Formes"].tap()
        XCTAssertTrue(app.buttons["Rectangle"].waitForExistence(timeout: 5))
        app.buttons["Rectangle"].tap()
        let fill = app.switches["Remplir la forme"].firstMatch
        XCTAssertTrue(fill.waitForExistence(timeout: 5))
        XCTAssertEqual(fill.value as? String, "0")
        let knob = fill.switches.firstMatch
        if knob.exists { knob.tap() } else { fill.tap() }
        let filled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: fill)
        XCTAssertEqual(XCTWaiter.wait(for: [filled], timeout: 5), .completed)
        app.buttons["editor.shape.save"].tap()
        waitForShapeSheetToClose(app)
        capture(app, "Rectangle rempli sur la page")
        app.buttons["editor.insert"].tap()
        app.buttons["Formes"].tap()
        XCTAssertTrue(app.buttons["Rectangle 1"].waitForExistence(timeout: 5))
        app.buttons["Rectangle 1"].tap()
        XCTAssertTrue(fill.waitForExistence(timeout: 5))
        XCTAssertEqual(fill.value as? String, "1", "Le remplissage doit rester enregistré lors de la réouverture")
        let delete = app.buttons["Supprimer la forme"]
        for _ in 0..<5 where !delete.isHittable { app.swipeUp() }
        XCTAssertTrue(delete.isHittable)
        delete.tap()
        waitForShapeSheetToClose(app)
        capture(app, "Suppression du rectangle")
        let undo = app.buttons["Annuler"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 5)); XCTAssertTrue(undo.isEnabled); XCTAssertTrue(undo.isHittable)
        undo.tap()
        app.buttons["editor.insert"].tap()
        app.buttons["Formes"].tap()
        XCTAssertTrue(app.buttons["Rectangle 1"].waitForExistence(timeout: 5))
        app.buttons["Rectangle 1"].tap()
        XCTAssertTrue(fill.waitForExistence(timeout: 5))
        XCTAssertEqual(fill.value as? String, "1", "Annuler la suppression doit restaurer le remplissage")
        capture(app, "Rectangle restauré avec son remplissage")
        app.buttons["Annuler"].firstMatch.tap()
    }

    func testTextCreationEditingAndNativeRulerSurviveRelaunch() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-nativeTools", "NO", "-inkTool", "lasso", "-openNotebooks", "()", "-activeNotebook", ""]
        app.launch()
        app.launchArguments = ["-nativeTools", "NO"]
        defer { app.terminate() }
        if app.buttons["workspace.library"].waitForExistence(timeout: 3) { app.buttons["workspace.library"].tap() }
        XCTAssertTrue(app.buttons["library.create"].waitForExistence(timeout: 10))
        app.buttons["library.create"].tap()
        let ruler = app.buttons["editor.ruler"]
        XCTAssertTrue(ruler.waitForExistence(timeout: 10))
        if !ruler.isSelected { ruler.tap() }
        XCTAssertTrue(ruler.isSelected)
        XCTAssertTrue(app.buttons["Stylo"].isSelected, "Activer la règle depuis le lasso doit revenir à un instrument d’écriture")
        app.buttons["editor.insert"].tap()
        app.buttons["Texte"].tap()
        XCTAssertTrue(app.buttons["Ajouter du texte"].waitForExistence(timeout: 5))
        app.buttons["Ajouter du texte"].tap()
        let content = app.textViews["editor.text.content"]
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        content.tap(); content.typeText("Texte persistant")
        app.buttons["editor.text.save"].tap()
        XCTAssertTrue(ruler.waitForExistence(timeout: 5))
        capture(app, "Texte et règle native sur iPad")
        app.terminate(); app.launch()
        XCTAssertTrue(ruler.waitForExistence(timeout: 10))
        XCTAssertTrue(ruler.isSelected, "La règle doit conserver son activation après relancement")
        app.buttons["editor.insert"].tap()
        app.buttons["Texte"].tap()
        app.buttons["Texte persistant"].tap()
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        XCTAssertEqual(content.value as? String, "Texte persistant")
        content.tap(); content.typeText(" modifié")
        app.buttons["editor.text.save"].tap()
        XCTAssertTrue(ruler.waitForExistence(timeout: 5))
        ruler.tap(); XCTAssertFalse(ruler.isSelected)
        capture(app, "Texte modifié après réouverture")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func waitForShapeSheetToClose(_ app: XCUIApplication) {
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["editor.shape.save"])
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
    }
}
