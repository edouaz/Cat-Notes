import XCTest
import SwiftUI
import UIKit
import PDFKit
@testable import OpenNotes

@MainActor
final class TextElementTests: XCTestCase {
    func testTextCreateEditDeleteUndoRedoReopenAndPDFExport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(root: directory); await store.load()
        let created = await store.create(); let id = try XCTUnwrap(created)
        let session = EditorSession(store: store, noteID: id); await session.open()
        let pageID = try XCTUnwrap(session.page?.id)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = UIScreen.main.bounds
        window.rootViewController = UIHostingController(rootView: WritingCanvas(session: session, finger: false, reading: false))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(nanoseconds: 100_000_000)
        let undo = try XCTUnwrap(session.canvas.undoManager); undo.removeAllActions()
        var text = PageElement(kind: .text, x: 40, y: 60, width: 300, height: 150, text: "Initial text")
        var saved = await session.apply(.init(pageID: pageID, kind: .upsertElement, element: text))
        XCTAssertTrue(saved)
        XCTAssertEqual(session.page?.elements, [text])
        try await Task.sleep(nanoseconds: 50_000_000)
        undo.removeAllActions()
        text.text = "Edited and preserved text"
        text.x = 90; text.width = 350
        saved = await session.apply(.init(pageID: pageID, kind: .upsertElement, element: text))
        XCTAssertTrue(saved)
        try await Task.sleep(nanoseconds: 50_000_000)
        undo.undo()
        XCTAssertEqual(session.page?.elements?.first?.text, "Initial text")
        XCTAssertEqual(session.page?.elements?.first?.x, 40)
        XCTAssertTrue(undo.canRedo); undo.redo()
        XCTAssertEqual(session.page?.elements, [text])
        saved = await session.flush(); XCTAssertTrue(saved)
        let reopened = EditorSession(store: store, noteID: id); await reopened.open(pageID)
        XCTAssertEqual(reopened.page?.elements, [text])
        XCTAssertTrue(try XCTUnwrap(reopened.page).searchableText.contains(text.text))
        let note = try XCTUnwrap(store.library.note(id: id)), page = try XCTUnwrap(reopened.page)
        let archive = NotebookArchive(note: note, pages: [page], resources: [page.drawingResourceID: reopened.drawing.dataRepresentation()])
        let output = directory.appendingPathComponent("text.pdf")
        try PageRenderer.export(archive, indices: 0...0, output: output)
        XCTAssertTrue(try XCTUnwrap(PDFDocument(url: output)?.string).contains(text.text))
        undo.removeAllActions()
        saved = await session.apply(.init(pageID: pageID, kind: .removeElement, elementID: text.id)); XCTAssertTrue(saved)
        XCTAssertTrue(session.page?.elements?.isEmpty == true)
        try await Task.sleep(nanoseconds: 50_000_000)
        undo.undo(); XCTAssertEqual(session.page?.elements, [text])
        undo.redo(); XCTAssertTrue(session.page?.elements?.isEmpty == true)
        saved = await session.flush(); XCTAssertTrue(saved)
        let deleted = EditorSession(store: store, noteID: id); await deleted.open(pageID)
        XCTAssertTrue(deleted.page?.elements?.isEmpty == true)
    }
}
