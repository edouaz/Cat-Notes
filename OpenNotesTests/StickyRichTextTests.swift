import XCTest
import UIKit
import PDFKit
@testable import OpenNotes

@MainActor
final class StickyRichTextTests: XCTestCase {
    func testRichTextRoundTripPreservesRunsAndParagraphs() throws {
        let text = NSMutableAttributedString(string: "Bold text\nمرحبا 👋", attributes: [.font: UIFont.systemFont(ofSize: 18), .foregroundColor: UIColor.blue])
        text.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: 18), range: NSRange(location: 0, length: 4))
        text.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 5, length: 4))
        let style = NSMutableParagraphStyle(); style.alignment = .right
        text.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: text.length))
        let decoded = try RichTextDocument.decode(RichTextDocument.encode(text))
        XCTAssertEqual(decoded.string, text.string)
        XCTAssertTrue(try XCTUnwrap(decoded.attribute(.font, at: 0, effectiveRange: nil) as? UIFont).fontDescriptor.symbolicTraits.contains(.traitBold))
        XCTAssertFalse(try XCTUnwrap(decoded.attribute(.font, at: 5, effectiveRange: nil) as? UIFont).fontDescriptor.symbolicTraits.contains(.traitBold))
        XCTAssertEqual(decoded.attribute(.underlineStyle, at: 5, effectiveRange: nil) as? Int, 1)
        XCTAssertEqual((decoded.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment, .right)
    }
    func testFormattingChangesOnlySelectionAndTypingAttributes() {
        let view = UITextView()
        view.attributedText = NSAttributedString(string: "one two", attributes: [.font: UIFont.systemFont(ofSize: 16)])
        let formatting = RichTextFormatting(); formatting.view = view
        view.selectedRange = NSRange(location: 0, length: 3)
        formatting.trait(.traitBold)
        XCTAssertTrue((view.attributedText.attribute(.font, at: 0, effectiveRange: nil) as! UIFont).fontDescriptor.symbolicTraits.contains(.traitBold))
        XCTAssertFalse((view.attributedText.attribute(.font, at: 4, effectiveRange: nil) as! UIFont).fontDescriptor.symbolicTraits.contains(.traitBold))
        view.selectedRange = NSRange(location: 7, length: 0)
        let before = view.attributedText.string
        formatting.toggle(.strikethroughStyle)
        XCTAssertEqual(view.attributedText.string, before)
        XCTAssertEqual(view.typingAttributes[.strikethroughStyle] as? Int, 1)
    }
    func testLegacyStickyDecodeAndNewFieldsRoundTrip() throws {
        var note = PageElement(kind: .stickyNote, text: "Persisted")
        let legacy = try JSONDecoder().decode(PageElement.self, from: JSONEncoder().encode(note))
        XCTAssertNil(legacy.richTextRTF); XCTAssertNil(legacy.isLocked); XCTAssertNil(legacy.rotation)
        note.richTextRTF = try RichTextDocument.encode(NSAttributedString(string: note.text, attributes: [.font: UIFont.italicSystemFont(ofSize: 20)]))
        note.fillColorHex = "#CCEEFF"; note.rotation = .pi / 3; note.collapsed = true; note.isLocked = true
        XCTAssertEqual(try JSONDecoder().decode(PageElement.self, from: JSONEncoder().encode(note)), note)
        let page = NotePage(noteID: UUID(), index: 0, format: .a4Portrait, template: .blank, drawingResourceID: "ink.drawing")
        XCTAssertNoThrow(try DocumentAction(pageID: page.id, kind: .upsertElement, element: note).applying(to: page))
        note.text = "mismatched text"
        XCTAssertThrowsError(try DocumentAction(pageID: page.id, kind: .upsertElement, element: note).applying(to: page))
        XCTAssertThrowsError(try RichTextDocument.decode(Data("invalid rtf".utf8)))
    }
    func testLockedStickyRejectsResizeAndCollapse() {
        var note = PageElement(kind: .stickyNote, text: "Locked")
        note.isLocked = true
        let control = StickyNoteControl(item: note)
        control.pageSize = CGSize(width: 794, height: 1123)
        var writes = 0; control.changed = { _ in writes += 1 }
        control.resizeNote(to: CGSize(width: 400, height: 400))
        control.toggleCollapsed()
        XCTAssertEqual(control.item, note)
        XCTAssertEqual(writes, 0)
    }
    func testCollapsedExportDoesNotRevealText() throws {
        var page = NotePage(noteID: UUID(), index: 0, format: .a4Portrait, template: .blank, drawingResourceID: "ink.drawing")
        var note = PageElement(kind: .stickyNote, text: "PRIVATE STICKY CONTENT")
        note.richTextRTF = try RichTextDocument.encode(NSAttributedString(string: note.text, attributes: [.font: UIFont.systemFont(ofSize: 16)]))
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: PageRenderer.size(page)))
        func pdf(_ collapsed: Bool) -> String {
            note.collapsed = collapsed; page.elements = [note]
            return PDFDocument(data: renderer.pdfData { context in
                context.beginPage(); PageRenderer.composite(page, data: nil, drawing: InkDrawing(), context: context.cgContext)
            })?.string ?? ""
        }
        XCTAssertTrue(pdf(false).contains(note.text))
        XCTAssertFalse(pdf(true).contains(note.text))
    }
}
