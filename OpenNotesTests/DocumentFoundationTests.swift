import XCTest
import PDFKit
import UIKit
@testable import OpenNotes

@MainActor
final class DocumentFoundationTests: XCTestCase {
    private func page() -> NotePage {
        NotePage(noteID: UUID(), index: 0, format: .a4Portrait, template: .blank, drawingResourceID: "ink.drawing")
    }
    func testOldPagesStillDecodeAndStickyNotesRoundTrip() throws {
        let original = page()
        let bytes = try JSONEncoder().encode(original)
        var decoded = try JSONDecoder().decode(NotePage.self, from: bytes)
        XCTAssertNil(decoded.pdfText); XCTAssertNil(decoded.ocrText)
        var sticky = PageElement(kind: .stickyNote); sticky.text = "Item to verify"; sticky.collapsed = true
        decoded = try DocumentAction(pageID: decoded.id, kind: .upsertElement, element: sticky).applying(to: decoded)
        let restored = try JSONDecoder().decode(NotePage.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(restored.elements?.first, sticky)
        XCTAssertTrue(restored.searchableText.contains("Item to verify"))
        XCTAssertEqual(restored.drawingResourceID, original.drawingResourceID)
    }
    func testActionsRejectInvalidGeometryAndStaleTargets() throws {
        var original = page(); original.revision = 2
        var element = PageElement(kind: .rectangle); element.x = .infinity
        XCTAssertThrowsError(try DocumentAction(pageID: original.id, kind: .upsertElement, element: element).applying(to: original))
        element.x = 1000
        XCTAssertThrowsError(try DocumentAction(pageID: original.id, kind: .upsertElement, element: element).applying(to: original))
        XCTAssertThrowsError(try DocumentAction(pageID: UUID(), kind: .setBookmark, bookmark: true).applying(to: original))
        XCTAssertThrowsError(try DocumentAction(pageID: original.id, kind: .setBookmark, bookmark: true, expectedRevision: 1).applying(to: original))
        let marked = try DocumentAction(pageID: original.id, kind: .setBookmark, bookmark: true, expectedRevision: original.revision).applying(to: original)
        XCTAssertEqual(marked.bookmark, true)
    }
    func testPDFTextIsSeparatedFromOCRWithLocatedLines() throws {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 600)
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            context.beginPage()
            ("Hello world" as NSString).draw(at: CGPoint(x: 40, y: 60), withAttributes: [.font: UIFont.systemFont(ofSize: 18)])
            context.beginPage()
        }
        let content = try PDFTextIndex.extract(data)
        XCTAssertEqual(content.count, 2)
        XCTAssertEqual(content[0].source, .pdf); XCTAssertEqual(content[0].status, .available)
        XCTAssertTrue(content[0].text.contains("Hello"))
        let line = try XCTUnwrap(content[0].blocks.first)
        XCTAssertGreaterThan(line.width, 0); XCTAssertGreaterThanOrEqual(line.y, 40); XCTAssertLessThan(line.y, 120)
        XCTAssertNil(line.confidence)
        XCTAssertEqual(content[1].status, .needsRecognition)
        var original = page(); original.pdfText = content[0]; original.drawingRevision = 2
        original.ocrText = PageTextContent(source: .ocr, status: .needsReview, text: "legacy handwriting", blocks: [], drawingRevision: 1)
        XCTAssertTrue(original.searchableText.contains("Hello")); XCTAssertFalse(original.searchableText.contains("legacy handwriting"))
    }
    func testTextGeometryIsValidatedAndOldArchiveVersionStillOpens() throws {
        var original = page()
        original.pdfText = .init(source: .pdf, status: .available, text: "Text", blocks: [.init(text: "Text", x: .infinity, y: 0, width: 100, height: 20)])
        XCTAssertFalse(NotebookArchive.validText(original.pdfText))
        original.pdfText = nil
        let note = NoteDocument(id: original.noteID, folderID: UUID(), title: "Legacy", pageIDs: [original.id])
        var archive = NotebookArchive(note: note, pages: [original], resources: [original.drawingResourceID: InkDrawing().dataRepresentation()])
        XCTAssertEqual(archive.version, 2)
        archive.version = 1; XCTAssertNoThrow(try archive.validate())
    }
    func testCaptureUsesRectangleAtPageCoordinatesAndNormalScale() throws {
        let original = page()
        let image = try PageRenderer.capture(original, data: nil, drawing: InkDrawing(), resources: [:], rect: CGRect(x: 40, y: 80, width: 200, height: 100))
        XCTAssertEqual(image.scale, 1)
        XCTAssertEqual(image.size.width / image.size.height, 2, accuracy: 0.01)
        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 2048)
        XCTAssertThrowsError(try PageRenderer.capture(original, data: nil, drawing: InkDrawing(), resources: [:], rect: CGRect(x: -300, y: -300, width: 10, height: 10)))
    }
    func testPaperReplacementRequiresConfirmationForImportedBackgroundOrDifferentSize() {
        let original = page()
        var lined = original; lined.template = .ruled
        XCTAssertFalse(PaperSheet.requiresConfirmation(from: original, to: lined))
        var imported = original; imported.backgroundID = "source.pdf"; imported.pdfIndex = 2
        XCTAssertTrue(PaperSheet.requiresConfirmation(from: imported, to: lined))
        XCTAssertFalse(PaperSheet.requiresConfirmation(from: imported, to: imported))
        var otherPDFPage = imported; otherPDFPage.pdfIndex = 3
        XCTAssertTrue(PaperSheet.requiresConfirmation(from: imported, to: otherPDFPage))
        var resized = original; resized.width = 200; resized.height = 300
        XCTAssertTrue(PaperSheet.requiresConfirmation(from: original, to: resized))
    }
    func testDoubleTapAlternatesFullPageAndWidthAroundTappedLocation() {
        let view = PageScrollView(canvas: InkCanvasView())
        view.frame = CGRect(x: 0, y: 0, width: 800, height: 500)
        view.pageSize = CGSize(width: 794, height: 1123); view.layoutIfNeeded()
        let full = view.canvas.minimumZoomScale
        view.toggleFit(at: CGPoint(x: 400, y: 300))
        XCTAssertGreaterThan(view.canvas.zoomScale, full)
        XCTAssertEqual(view.canvas.zoomScale, (800 - 32) / 794, accuracy: 0.01)
        view.toggleFit(at: CGPoint(x: 400, y: 300))
        XCTAssertEqual(view.canvas.zoomScale, full, accuracy: 0.01)
    }
    func testReadableContextIncludesSemanticAnnotationsAndStrokeData() throws {
        var original = page()
        original.elements = [PageElement(kind: .stickyNote, text: "Question ouverte", collapsed: true)]
        let note = NoteDocument(id: original.noteID, folderID: UUID(), title: "Lecture", pageIDs: [original.id])
        let archive = NotebookArchive(note: note, pages: [original], resources: [original.drawingResourceID: InkDrawing().dataRepresentation()])
        let context = try DocumentContext(archive: archive)
        let encoded = try JSONEncoder().encode(context)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(json["formatVersion"] as? Int, 1)
        XCTAssertTrue(String(decoding: encoded, as: UTF8.self).contains("Question ouverte"))
        XCTAssertEqual(context.pages.first?.strokes.count, 0)
    }
}
