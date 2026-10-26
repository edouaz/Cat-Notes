import XCTest
import UIKit

@MainActor
final class ToolPersonalizationTests: XCTestCase {
    private let app = XCUIApplication()
    private var favorites: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Couleur favorite "))
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
            screenshot("Personnalisation — échec")
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "Personnalisation — hiérarchie"; tree.lifetime = .keepAlways; add(tree)
        }
        app.terminate()
    }

    func testToolVisibilityAndSeparateFavoritesPersistAfterRelaunch() throws {
        openCustomization()
        let labels = ["Stylo", "Crayon", "Surligneur", "Lasso", "Couleurs favorites sur iPad"]
        var initialVisibility: [String: Bool] = [:]
        for label in labels {
            let control = toggle(label)
            reveal(control)
            initialVisibility[label] = control.value as? String == "1"
        }
        setToggle("Stylo", true); setToggle("Surligneur", true)
        setToggle("Lasso", true); setToggle("Crayon", false)
        setToggle("Couleurs favorites sur iPad", true)
        closeCustomization()
        XCTAssertFalse(app.buttons["Crayon"].exists)
        XCTAssertTrue(app.buttons["Lasso"].exists)
        screenshot("Crayon masqué avant personnalisation")

        openCustomization()
        setToggle("Crayon", true); setToggle("Lasso", false)
        closeCustomization()
        assertPersonalizedToolbar()
        screenshot("Crayon affiché et lasso masqué dans la barre")

        selectTool("Stylo")
        let penBefore = favoriteValues()
        selectTool("Surligneur")
        let markerBefore = favoriteValues()
        guard penBefore.count < 64, markerBefore.count < 64 else {
            restoreVisibility(initialVisibility)
            throw XCTSkip("L’ajout nécessite une place libre parmi les 64 favoris de chaque outil ; aucun favori existant n’est supprimé.")
        }

        selectTool("Stylo")
        let penAfter = try addFavoriteOfSelectedTool()
        XCTAssertEqual(Array(penAfter.dropLast()), penBefore)
        let selectedFavorite = app.buttons["Couleur favorite \(penAfter.count)"]
        revealFavorite(selectedFavorite)
        XCTAssertTrue(selectedFavorite.isSelected)
        selectedFavorite.tap()
        XCTAssertTrue(app.staticTexts["Modifier la favorite"].waitForExistence(timeout: 5),
                      "Retoucher la couleur active doit ouvrir son éditeur")
        screenshot("Retoucher une favorite active ouvre sa modification")
        let title = app.staticTexts["Modifier la favorite"].frame
        let cancel = try XCTUnwrap(app.buttons.matching(identifier: "Annuler").allElementsBoundByIndex.first {
            $0.isHittable && $0.frame.minY > title.maxY
        })
        cancel.tap()
        waitUntilGone(app.staticTexts["Modifier la favorite"])
        XCTAssertEqual(favoriteValues(), penAfter, "Annuler l’édition doit conserver la couleur et son ordre")

        selectTool("Surligneur")
        XCTAssertEqual(favoriteValues(), markerBefore, "Ajouter au stylo ne doit pas modifier les favoris du surligneur")
        let markerAfter = try addFavoriteOfSelectedTool()
        XCTAssertEqual(Array(markerAfter.dropLast()), markerBefore)
        screenshot("Favoris du surligneur après ajout indépendant")
        selectTool("Stylo")
        XCTAssertEqual(favoriteValues(), penAfter, "Ajouter au surligneur ne doit pas modifier les favoris du stylo")
        screenshot("Favoris du stylo conservés après changement d’outil")

        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["editor.pages"].waitForExistence(timeout: 10))
        assertPersonalizedToolbar()
        selectTool("Stylo"); XCTAssertEqual(favoriteValues(), penAfter)
        selectTool("Surligneur"); XCTAssertEqual(favoriteValues(), markerAfter)
        screenshot("Visibilité et favoris propres aux outils après relancement")
        restoreVisibility(initialVisibility)

        let scope = XCTAttachment(string: "Parcours tactile : crayon masqué puis affiché, lasso masqué, ajout et sélection d’une favorite pour chaque outil, indépendance des listes et conservation au relancement. Retoucher la favorite active ouvre Modifier ; annuler conserve la liste. Le réordonnancement et le choix d’une nouvelle couleur dans le panneau système ne sont pas exercés. La visibilité initiale est restaurée ; les deux favoris ajoutés et le carnet créé sont conservés.")
        scope.name = "Portée du parcours de personnalisation"; scope.lifetime = .keepAlways; add(scope)
    }

    func testFingerPenStrokeDisappearsWithOneUndoAndReturnsWithRedo() throws {
        app.terminate()
        app.launchArguments += ["-fingerDrawing", "YES", "-showUndo", "YES", "-showInkColor", "YES", "-showInkWidth", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["editor.pages"].waitForExistence(timeout: 10))
        openCustomization(); setToggle("Stylo", true); closeCustomization()
        selectTool("Stylo")
        let dark = try XCTUnwrap(favorites.allElementsBoundByIndex.first { color in
            guard let hex = color.value as? String, hex.count == 7,
                  let rgb = UInt32(hex.dropFirst(), radix: 16) else { return false }
            return (rgb >> 16) < 90 && ((rgb >> 8) & 255) < 90 && (rgb & 255) < 90
        }, "Le contrôle de pixels nécessite un favori foncé, distinct du quadrillage")
        revealFavorite(dark)
        if !dark.isSelected { dark.tap() }
        let thick = app.buttons["Épaisseur 6 points"]
        XCTAssertTrue(thick.isHittable); thick.tap()

        for (index, style) in ["Bille", "Plume"].enumerated() {
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
            if index == 0 { XCTAssertFalse(app.buttons["Annuler"].isEnabled, "Le carnet neuf doit commencer sans historique") }
            screenshot("\(style) — zone centrale avant le trait")

            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: start.x - app.frame.minX, dy: start.y - app.frame.minY))
                .press(forDuration: 0.05,
                       thenDragTo: origin.withOffset(CGVector(dx: end.x - app.frame.minX, dy: end.y - app.frame.minY)),
                       withVelocity: .slow, thenHoldForDuration: 0.05)
            let undo = app.buttons["Annuler"]
            let undoReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: undo)
            XCTAssertEqual(XCTWaiter.wait(for: [undoReady], timeout: 5), .completed)
            let drawn = waitForDarkPixels(in: roi, phase: "\(style) : trait ajouté", matching: { $0 > baseline + 200 })
            screenshot("\(style) — trait visible au doigt")

            undo.tap()
            let tolerance = max(12, (drawn - baseline) / 50)
            _ = waitForDarkPixels(in: roi, phase: "\(style) : après UNE annulation, fond attendu \(baseline)",
                                  matching: { $0 <= baseline + tolerance })
            screenshot("\(style) — une annulation retire le trait")
            if index == 0 { XCTAssertFalse(undo.isEnabled, "Un trait unique ne doit pas laisser une seconde étape d’annulation de son profil") }

            let redo = app.buttons["Rétablir"]
            let redoReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: redo)
            XCTAssertEqual(XCTWaiter.wait(for: [redoReady], timeout: 5), .completed)
            redo.tap()
            _ = waitForDarkPixels(in: roi, phase: "\(style) : trait rétabli",
                                  matching: { $0 >= baseline + (drawn - baseline) * 4 / 5 })
            screenshot("\(style) — rétablir remet le trait visible")
        }
        setPenStyle("Bille")
    }

    private func setPenStyle(_ style: String) {
        selectTool("Stylo"); app.buttons["Stylo"].tap()
        XCTAssertTrue(app.navigationBars["Instrument"].waitForExistence(timeout: 5))
        let styles = ["Bille", "Plume", "Pinceau"]
        let picker = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ OR label IN %@ OR value IN %@",
                                                     "Type de stylo", styles, styles)).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5)); reveal(picker); picker.tap()
        let option = app.buttons[style]
        XCTAssertTrue(option.waitForExistence(timeout: 5)); option.tap()
        app.navigationBars["Instrument"].buttons["Terminé"].tap()
        waitUntilGone(app.navigationBars["Instrument"])
    }

    private func waitForDarkPixels(in roi: CGRect, phase: String, matching condition: @escaping (Int) -> Bool) -> Int {
        var measured = -1
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            measured = self.darkPixelCount(in: roi)
            return measured >= 0 && condition(measured)
        }, object: nil)
        let result = XCTWaiter.wait(for: [changed], timeout: 5)
        let reading = XCTAttachment(string: "\(phase) ; ROI en points : \(roi) ; pixels sombres : \(measured). Seuil : R, V et B < 90 et alpha > 200, pour exclure le quadrillage clair. Aucun second toucher Annuler n’est tenté.")
        reading.name = phase; reading.lifetime = .keepAlways; add(reading)
        XCTAssertEqual(result, .completed, "\(phase) ; pixels sombres observés : \(measured)")
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
        let customize = app.buttons["Personnaliser les outils"]
        XCTAssertTrue(customize.waitForExistence(timeout: 5))
        reveal(customize); customize.tap()
        XCTAssertTrue(app.navigationBars["Écriture"].waitForExistence(timeout: 5))
    }

    private func closeCustomization() {
        app.navigationBars["Écriture"].buttons["Terminé"].tap()
        waitUntilGone(app.navigationBars["Écriture"])
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
        XCTAssertTrue(app.buttons["Crayon"].isHittable)
        XCTAssertFalse(app.buttons["Lasso"].exists)
        XCTAssertTrue(app.buttons["Ajouter une couleur favorite"].isHittable)
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
            let color = app.buttons["Couleur favorite \(index)"]
            revealFavorite(color)
            if !color.isSelected { color.tap() }
            XCTAssertTrue(color.isSelected)
            selectedHex = color.value as? String
        }
        app.buttons["Ajouter une couleur favorite"].tap()
        XCTAssertTrue(app.staticTexts["Nouvelle favorite"].waitForExistence(timeout: 5))
        app.buttons["Ajouter"].tap()
        waitUntilGone(app.staticTexts["Nouvelle favorite"])
        let added = app.buttons["Couleur favorite \(before.count + 1)"]
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
        XCTAssertTrue(color.isHittable, "Les favoris doivent rester accessibles par défilement horizontal")
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
        XCTAssertTrue(element.isHittable, "Le réglage doit rester accessible dans le panneau")
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
