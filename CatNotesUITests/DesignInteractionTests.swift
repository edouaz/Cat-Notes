import XCTest
import UIKit

@MainActor
final class DesignInteractionTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-nativeTools", "NO", "-inkTool", "pen"]
        app.launch()
        let library = app.buttons["workspace.library"]
        if library.waitForExistence(timeout: 5) { library.tap() }
        XCTAssertTrue(app.buttons["library.create"].waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        if let testRun, testRun.failureCount > 0 {
            screenshot("Écran lors de l’échec")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Hiérarchie lors de l’échec"; hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        app.terminate()
    }

    func testLibrarySelectionClearsAcrossFilters() throws {
        let notebook = try createNotebook()
        app.buttons["library.select"].tap()
        app.buttons[notebook].tap()
        XCTAssertTrue(app.buttons["library.move"].waitForExistence(timeout: 5))
        screenshot("Sélection avant changement de filtre")

        selectFilter("Favoris")
        XCTAssertEqual(app.buttons["library.select"].label, "Sélectionner")
        XCTAssertFalse(app.buttons["library.move"].exists)
        screenshot("Favoris après remise à zéro de la sélection")

        selectFilter("Documents")
        XCTAssertEqual(app.buttons["library.select"].label, "Sélectionner")
        XCTAssertFalse(app.buttons["library.move"].exists)
        app.buttons[notebook].tap()
        XCTAssertTrue(app.buttons["editor.insert"].waitForExistence(timeout: 10), "Toucher un carnet doit l’ouvrir après le changement de filtre")
        screenshot("Carnet ouvert après changement de filtre")
    }

    func testUnmatchedSearchShowsSearchState() throws {
        _ = try createNotebook()
        screenshot("Bibliothèque avant recherche")
        let search = app.searchFields.firstMatch
        if !search.isHittable { app.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("catnotes-ui-no-match-\(UUID().uuidString)")
        XCTAssertTrue(app.staticTexts["Aucun résultat"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Une page pour vos idées"].exists)
        screenshot("Recherche sans résultat")
    }

    func testInstrumentSettingsAndCaptureActions() throws {
        let notebook = try createNotebook()
        app.buttons[notebook].tap()
        XCTAssertTrue(app.buttons["editor.insert"].waitForExistence(timeout: 10))
        screenshot("Éditeur avant réglages")
        for label in ["Stylo", "Surligneur", "Gomme", "Lasso", "Réglages de l’instrument"] {
            XCTAssertGreaterThanOrEqual(app.buttons[label].frame.width, 44)
            XCTAssertGreaterThanOrEqual(app.buttons[label].frame.height, 44)
        }
        app.buttons["Réglages de l’instrument"].tap()
        XCTAssertTrue(app.navigationBars["Instrument"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["Épaisseur du trait"].isHittable)
        screenshot("Réglages de l’instrument")
        app.buttons["Terminé"].tap()
        XCTAssertTrue(app.buttons["editor.insert"].isHittable)

        openPageCapture()
        for identifier in ["capture.copy", "capture.insert", "capture.share"] {
            XCTAssertTrue(app.buttons[identifier].isHittable, "La commande \(identifier) doit rester accessible")
        }
        screenshot("Capture avant copie")
        app.buttons["capture.copy"].tap()
        XCTAssertTrue(app.buttons["editor.insert"].waitForExistence(timeout: 5))
        waitUntilDismissed(app.buttons["capture.copy"])
        screenshot("Éditeur après copie")

        openPageCapture()
        app.buttons["capture.insert"].tap()
        let done = app.buttons["editor.mode.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        screenshot("Placement de la capture avant terminaison")
        done.tap()
        XCTAssertFalse(done.exists)
        XCTAssertTrue(app.buttons["editor.insert"].isHittable)
        screenshot("Éditeur après terminaison du placement")

        app.buttons["editor.insert"].tap()
        app.buttons["Recadrer / gérer les images"].tap()
        XCTAssertTrue(app.buttons["Modifier l’image 1"].waitForExistence(timeout: 5))
        app.buttons["Modifier l’image 1"].tap()
        XCTAssertTrue(app.navigationBars["Modifier l’image"].waitForExistence(timeout: 5))
        let crop = app.switches["Recadrer"]
        if crop.switches.firstMatch.exists { crop.switches.firstMatch.tap() }
        else { crop.tap() }
        XCTAssertTrue(app.sliders["Gauche"].waitForExistence(timeout: 5))
        for label in ["Gauche", "Haut", "Droite", "Bas"] {
            reveal(app.sliders[label])
            XCTAssertTrue(app.sliders[label].isHittable)
            XCTAssertTrue(app.staticTexts[label].exists)
        }
        screenshot("Recadrage avec libellés visibles")
        app.navigationBars["Modifier l’image"].buttons["Annuler"].tap()
        if done.waitForExistence(timeout: 5) { done.tap() }

        openPageCapture()
        let share = app.buttons["capture.share"]
        share.tap()
        let activity = app.otherElements["ActivityListView"]
        XCTAssertTrue(activity.waitForExistence(timeout: 10))
        XCTAssertTrue(activity.buttons["header.closeButton"].waitForExistence(timeout: 10))
        XCTAssertTrue(activity.buttons["header.closeButton"].isHittable)
        XCTAssertTrue(activity.collectionViews["activityCollectionView"].exists)
        let caption = activity.otherElements["LP.CaptionBar.TopCaption"]
        XCTAssertTrue(caption.waitForExistence(timeout: 5))
        XCTAssertTrue(caption.label.contains("Capture"))
        XCTAssertEqual(app.alerts.count, 0, "Le partage doit ouvrir la feuille système sans erreur")
        screenshot("Feuille système après partage de la capture")
    }

    func testAnnotationEditingDoesNotDeleteTheRow() throws {
        let notebook = try createNotebook()
        app.buttons[notebook].tap()
        XCTAssertTrue(app.buttons["editor.insert"].waitForExistence(timeout: 10))
        app.buttons["editor.insert"].tap()
        app.buttons["Post-it"].tap()
        let text = app.textViews["Texte du post-it"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.tap(); text.typeText("Annotation à conserver")
        app.buttons["Enregistrer"].tap()
        XCTAssertTrue(app.buttons["editor.actions"].waitForExistence(timeout: 5))
        app.buttons["editor.actions"].tap()
        app.buttons["Annotations de la page"].tap()
        XCTAssertTrue(app.staticTexts["Annotation à conserver"].waitForExistence(timeout: 5))
        screenshot("Annotation avant modification")
        app.buttons["Modifier"].tap()
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertEqual(text.value as? String, "Annotation à conserver")
        app.navigationBars["Post-it"].buttons["Annuler"].tap()
        app.buttons["editor.actions"].tap()
        app.buttons["Annotations de la page"].tap()
        XCTAssertTrue(app.staticTexts["Annotation à conserver"].waitForExistence(timeout: 5), "Modifier ne doit pas déclencher le bouton Supprimer de la même ligne")
        screenshot("Annotation conservée après annulation de la modification")
        app.buttons["Supprimer cette annotation"].tap()
        XCTAssertTrue(app.staticTexts["Aucune annotation sur cette page"].waitForExistence(timeout: 5))
    }

    func testReplacingImportedPaperCanBeCancelled() throws {
        guard #available(iOS 16.4, *) else { throw XCTSkip("L’ouverture d’URL depuis XCTest nécessite iOS 16.4") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Papier de référence \(UUID().uuidString).pdf")
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 600)).pdfData { context in
            context.beginPage()
            ("Document à conserver" as NSString).draw(at: CGPoint(x: 40, y: 60), withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
        }
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        app.open(url)
        XCTAssertTrue(app.buttons["editor.actions"].waitForExistence(timeout: 10))
        app.buttons["editor.actions"].tap()
        app.buttons["Modifier le papier"].tap()
        XCTAssertTrue(app.buttons["Ligné"].waitForExistence(timeout: 5))
        screenshot("Papier PDF avant remplacement")
        app.buttons["Ligné"].tap()
        XCTAssertTrue(app.buttons["Remplacer le fond"].waitForExistence(timeout: 5))
        screenshot("Confirmation avant remplacement du fond PDF")
        app.buttons["Annuler"].tap()
        XCTAssertTrue(app.buttons["Ligné"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Ligné"].isSelected)
        app.buttons["Ligné"].tap()
        XCTAssertTrue(app.buttons["Remplacer le fond"].waitForExistence(timeout: 5), "Annuler doit conserver le fond importé et demander à nouveau confirmation")
        app.buttons["Remplacer le fond"].tap()
        XCTAssertTrue(app.buttons["editor.actions"].waitForExistence(timeout: 5))
        app.buttons["editor.actions"].tap()
        app.buttons["Modifier le papier"].tap()
        XCTAssertTrue(app.buttons["Ligné"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Ligné"].isSelected)
        screenshot("Papier ligné après remplacement confirmé")
    }

    func testAccessibility5SelectionAndCaptureRemainReachable() throws {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let library = app.buttons["workspace.library"]
        if library.waitForExistence(timeout: 5) { library.tap() }
        XCTAssertTrue(app.buttons["library.create"].waitForExistence(timeout: 10))

        let notebook = try createNotebook()
        let selection = app.buttons["library.select"]
        reveal(selection, towardTop: true)
        selection.tap()
        XCTAssertEqual(selection.label, "Terminé")
        let note = app.buttons[notebook]
        reveal(note)
        note.tap()
        XCTAssertEqual(note.value as? String, "Sélectionné")
        reveal(app.buttons["library.move"], towardTop: true)
        XCTAssertTrue(app.buttons["library.move"].isHittable)
        XCTAssertTrue(app.buttons["library.filter"].exists, "Les grands caractères doivent proposer le filtre compact")
        screenshot("AX5 sélection avant changement de filtre")

        selectFilter("Favoris")
        reveal(selection, towardTop: true)
        XCTAssertEqual(selection.label, "Sélectionner")
        XCTAssertFalse(app.buttons["library.move"].exists)
        selectFilter("Documents")
        XCTAssertEqual(selection.label, "Sélectionner")
        XCTAssertFalse(app.buttons["library.move"].exists)
        reveal(note, tappingCenter: true)
        note.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["editor.insert"].waitForExistence(timeout: 10))
        waitUntilDismissed(app.keyboards.firstMatch)

        app.buttons["editor.insert"].tap()
        reveal(app.buttons["Capturer une zone"])
        app.buttons["Capturer une zone"].tap()
        let done = app.buttons["editor.mode.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(done.isHittable)
        XCTAssertEqual(done.label, "Annuler")
        XCTAssertGreaterThanOrEqual(done.frame.height, 44)
        screenshot("AX5 mode capture avant annulation")
        done.tap()
        XCTAssertFalse(done.exists)
        XCTAssertTrue(app.buttons["editor.insert"].isHittable)

        openPageCapture()
        for identifier in ["capture.copy", "capture.insert", "capture.share"] {
            let action = app.buttons[identifier]
            reveal(action)
            XCTAssertTrue(action.isHittable, "La commande \(identifier) doit être accessible après défilement en AX5")
            XCTAssertGreaterThanOrEqual(action.frame.width, 44)
            XCTAssertGreaterThanOrEqual(action.frame.height, 44)
        }
        screenshot("AX5 actions de capture après défilement")
        let copy = app.buttons["capture.copy"]
        reveal(copy, towardTop: true)
        copy.tap()
        XCTAssertTrue(app.buttons["editor.insert"].waitForExistence(timeout: 5))
        waitUntilDismissed(copy)
        screenshot("AX5 éditeur après copie")
    }

    func testFolderBreadcrumbsMoveAndTrashRecovery() throws {
        let token = UUID().uuidString.prefix(8)
        let title = "Carnet UI \(token)"
        let parent = "Dossier UI \(token)", child = "1"
        let notebook = try createNotebook()
        try renameNotebook(notebook, to: title)

        createFolder(named: parent)
        reveal(app.buttons[parent]); app.buttons[parent].tap()
        createFolder(named: child)
        reveal(app.buttons[child]); app.buttons[child].tap()
        let parentBreadcrumb = app.scrollViews.buttons[parent].firstMatch
        reveal(parentBreadcrumb, towardTop: true)
        XCTAssertGreaterThanOrEqual(parentBreadcrumb.frame.height, 44)
        let childBreadcrumb = app.scrollViews.buttons[child].firstMatch
        XCTAssertGreaterThanOrEqual(childBreadcrumb.frame.width, 44)
        XCTAssertGreaterThanOrEqual(childBreadcrumb.frame.height, 44)
        screenshot("Dossiers imbriqués et fil d’Ariane")
        parentBreadcrumb.tap()
        XCTAssertTrue(app.buttons[child].waitForExistence(timeout: 5))
        let rootBreadcrumb = app.scrollViews.buttons["Documents"].firstMatch
        XCTAssertGreaterThanOrEqual(rootBreadcrumb.frame.height, 44)
        rootBreadcrumb.tap()

        let select = app.buttons["library.select"]
        reveal(select, towardTop: true)
        XCTAssertGreaterThanOrEqual(select.frame.height, 44)
        select.tap()
        let note = app.buttons[notebook]
        reveal(note); note.tap()
        XCTAssertEqual(note.value as? String, "Sélectionné")
        let move = app.buttons["library.move"]
        reveal(move, towardTop: true)
        XCTAssertGreaterThanOrEqual(move.frame.height, 44)
        move.tap()
        XCTAssertTrue(app.navigationBars["Déplacer vers…"].waitForExistence(timeout: 5))
        let destination = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "\(parent) / \(child)")).firstMatch
        reveal(destination); destination.tap()
        waitUntilDismissed(app.navigationBars["Déplacer vers…"])
        waitUntilDismissed(note)
        XCTAssertEqual(select.label, "Sélectionner")
        reveal(app.buttons[parent], towardTop: true); app.buttons[parent].tap()
        reveal(app.buttons[child]); app.buttons[child].tap()
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertEqual(note.label, title)
        screenshot("Carnet déplacé dans le sous-dossier")

        let actions = app.buttons["Actions pour \(title)"]
        reveal(actions); actions.tap()
        app.buttons["Placer dans la corbeille"].tap()
        XCTAssertTrue(app.staticTexts["Placer ce carnet dans la corbeille ?"].waitForExistence(timeout: 5))
        app.buttons["Placer dans la corbeille"].tap()
        waitUntilDismissed(note)
        selectFilter("Corbeille")
        reveal(note, tappingCenter: true)
        XCTAssertFalse(note.isEnabled)
        XCTAssertEqual(note.value as? String, "Dans la corbeille")
        XCTAssertFalse(select.exists)
        XCTAssertFalse(move.exists)
        screenshot("Corbeille avec statut explicite et carte désactivée")
        reveal(actions); actions.tap()
        XCTAssertTrue(app.buttons["Récupérer le carnet"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Déplacer vers…"].exists)
        app.buttons["Récupérer le carnet"].tap()
        waitUntilDismissed(note)

        selectFilter("Documents")
        reveal(app.buttons[parent]); app.buttons[parent].tap()
        reveal(app.buttons[child]); app.buttons[child].tap()
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertTrue(note.isEnabled)
        screenshot("Carnet récupéré dans son sous-dossier")
        reveal(note, tappingCenter: true)
        note.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["editor.insert"].waitForExistence(timeout: 10))
    }

    func testSixTabsRestoreActiveAndCloseByName() throws {
        let token = UUID().uuidString.prefix(8)
        var entries: [(id: String, title: String)] = []
        for index in 1...6 {
            let id = try createNotebook()
            let title = "Onglet \(index) UI \(token)"
            try renameNotebook(id, to: title)
            entries.append((id, title))
        }
        let first = try XCTUnwrap(entries.first), last = try XCTUnwrap(entries.last)
        reveal(app.buttons[last.id]); app.buttons[last.id].tap()
        XCTAssertTrue(app.buttons["editor.insert"].waitForExistence(timeout: 10))
        let firstTab = app.buttons[first.title], lastTab = app.buttons[last.title]
        let tabs = app.scrollViews.containing(.button, identifier: first.title).firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 5), "Ce parcours nécessite les onglets visibles d’un iPad en taille normale")
        waitForSelectedTab(lastTab)
        for entry in entries { XCTAssertTrue(app.buttons[entry.title].exists) }
        screenshot("Six onglets avec le dernier actif et visible")

        for tab in [firstTab, lastTab] {
            for _ in 0..<10 {
                let frame = tab.frame, viewport = tabs.frame
                if !frame.isEmpty && viewport.contains(frame) { break }
                let towardBeginning = frame.midX < viewport.midX
                let start = tabs.coordinate(withNormalizedOffset: CGVector(dx: towardBeginning ? 0.25 : 0.75, dy: 0.75))
                let end = tabs.coordinate(withNormalizedOffset: CGVector(dx: towardBeginning ? 0.75 : 0.25, dy: 0.75))
                // Hold before lifting so momentum does not skip the requested tab.
                start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
            }
            XCTAssertFalse(tab.frame.isEmpty)
            XCTAssertTrue(tabs.frame.contains(tab.frame))
            XCTAssertTrue(tab.isHittable)
            tab.tap()
            waitForSelectedTab(tab)
        }
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["editor.insert"].waitForExistence(timeout: 10))
        waitForSelectedTab(lastTab)
        for entry in entries { XCTAssertTrue(app.buttons[entry.title].exists) }
        screenshot("Onglet actif visible après restauration")

        let close = app.buttons["Fermer \(last.title)"]
        XCTAssertTrue(close.isHittable)
        XCTAssertGreaterThanOrEqual(close.frame.width, 44)
        XCTAssertGreaterThanOrEqual(close.frame.height, 44)
        close.tap()
        waitUntilDismissed(lastTab)
        for entry in entries.dropLast() { XCTAssertTrue(app.buttons[entry.title].exists) }
        screenshot("Onglet fermé par son nom et autres carnets conservés")
        app.buttons["workspace.library"].tap()
        reveal(app.buttons[last.id], tappingCenter: true)
        XCTAssertTrue(app.buttons[last.id].exists, "Fermer un onglet doit conserver le carnet dans la bibliothèque")
    }

    private func renameNotebook(_ identifier: String, to title: String) throws {
        let note = app.buttons[identifier]
        reveal(note, tappingCenter: true)
        let frame = note.frame
        // Untitled notebooks share a name; use the explicit menu next to this card.
        let actions = app.buttons.matching(identifier: "Actions pour \(note.label)").allElementsBoundByIndex.first {
            let menu = $0.frame
            return menu.midX >= frame.minX && menu.midX <= frame.maxX && menu.midY > frame.maxY && menu.midY < frame.maxY + 80
        }
        let menu = try XCTUnwrap(actions)
        reveal(menu); menu.tap()
        XCTAssertTrue(app.buttons["Renommer"].waitForExistence(timeout: 5))
        app.buttons["Renommer"].tap()
        let alert = app.alerts["Renommer le carnet"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let field = alert.textFields["Titre"]
        let previous = field.value as? String ?? ""
        field.tap(); field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + title)
        alert.buttons["Enregistrer"].tap()
        waitUntilDismissed(alert)
        XCTAssertEqual(note.label, title)
    }

    private func createFolder(named name: String) {
        let create = app.buttons["Dossier"]
        reveal(create, towardTop: true); create.tap()
        let field = app.textFields["Nom du dossier"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText(name)
        app.navigationBars["Nouveau dossier"].buttons["Enregistrer"].tap()
        waitUntilDismissed(app.navigationBars["Nouveau dossier"])
        XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 5))
    }

    private func waitForSelectedTab(_ tab: XCUIElement) {
        let active = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true AND isHittable == true"), object: tab)
        XCTAssertEqual(XCTWaiter.wait(for: [active], timeout: 5), .completed)
    }

    private func createNotebook() throws -> String {
        selectFilter("Documents")
        let previous = Set(notebooks.allElementsBoundByIndex.map(\.identifier))
        let create = app.buttons["library.create"]
        reveal(create, towardTop: true)
        create.tap()
        XCTAssertTrue(app.buttons["editor.insert"].waitForExistence(timeout: 10))
        app.buttons["workspace.library"].tap()
        XCTAssertTrue(app.buttons["library.select"].waitForExistence(timeout: 10))
        let created = notebooks.matching(NSPredicate(format: "NOT (identifier IN %@)", argumentArray: [Array(previous)])).firstMatch
        reveal(created)
        return try XCTUnwrap(created.exists ? created.identifier : nil)
    }

    private var notebooks: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "library.note."))
    }

    private func selectFilter(_ title: String) {
        let filter = app.buttons["library.filter"]
        if filter.exists { reveal(filter, towardTop: true); filter.tap(); app.buttons[title].firstMatch.tap() }
        else { app.buttons[title].firstMatch.tap() }
        if title == "Corbeille" { XCTAssertTrue(app.navigationBars["Corbeille"].waitForExistence(timeout: 5)) }
        else { XCTAssertTrue(app.buttons["library.select"].waitForExistence(timeout: 5)) }
    }

    private func reveal(_ element: XCUIElement, towardTop: Bool = false, tappingCenter: Bool = false) {
        func reached() -> Bool {
            guard element.exists else { return false }
            if tappingCenter {
                return app.frame.contains(element.frame) && element.frame.minY >= app.navigationBars.firstMatch.frame.maxY
            }
            return element.isHittable
        }
        for _ in 0..<10 {
            if reached() { return }
            let containers = app.scrollViews.allElementsBoundByIndex + app.collectionViews.allElementsBoundByIndex
            guard let scroll = containers.first(where: { $0.isHittable }) else { break }
            // Native menus can report an unclipped full-screen collection frame.
            let clippedMenu = scroll.elementType == .collectionView && scroll.frame.height >= app.frame.height
            let midpoint = clippedMenu ? scroll.frame.minY + scroll.frame.height * 0.25 : scroll.frame.midY
            let towardBeginning = element.exists ? element.frame.midY < midpoint : towardTop
            let upper = clippedMenu ? 0.15 : towardBeginning ? 0.35 : 0.45
            let lower = clippedMenu ? 0.40 : towardBeginning ? 0.55 : 0.65
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: towardBeginning ? upper : lower))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: towardBeginning ? lower : upper))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(reached(), "Le contrôle demandé doit être atteignable par défilement")
    }

    private func openPageCapture() {
        app.buttons["editor.insert"].tap()
        reveal(app.buttons["Capturer la page entière"])
        app.buttons["Capturer la page entière"].tap()
        XCTAssertTrue(app.navigationBars["Capture"].waitForExistence(timeout: 10))
        reveal(app.buttons["capture.copy"])
    }

    private func waitUntilDismissed(_ element: XCUIElement) {
        let disappeared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [disappeared], timeout: 5), .completed)
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
