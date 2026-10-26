import XCTest
import SwiftUI
import PencilKit
import PDFKit
@testable import OpenNotes

@MainActor
final class CanvasTests: XCTestCase {
    func testPencilOnlyReadModeAndZoomWindow() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = LibraryStore(root: root); await store.load()
        let created = await store.create()
        let id = try XCTUnwrap(created)
        let editor = EditorSession(store: store, noteID: id); await editor.open()
        let host = UIHostingController(rootView: WritingCanvas(session: editor, finger: false, reading: false))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = UIScreen.main.bounds; window.rootViewController = host; window.makeKeyAndVisible()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(editor.canvas.drawingPolicy, .pencilOnly)
        let scroll = try XCTUnwrap(editor.canvas.superview as? PageScrollView)
        let paper = scroll.paper
        XCTAssertEqual(paper.center.x, scroll.bounds.width / 2, accuracy: 1)
        XCTAssertEqual(paper.center.y, scroll.bounds.height / 2, accuracy: 1)
        XCTAssertLessThanOrEqual(paper.frame.width, scroll.bounds.width)
        XCTAssertLessThanOrEqual(paper.frame.height, scroll.bounds.height)
        XCTAssertTrue(editor.canvas.isScrollEnabled)
        XCTAssertTrue(editor.canvas.transform.isIdentity)
        XCTAssertFalse(paper.isUserInteractionEnabled)
        let beforeZoom = editor.canvas.drawing.dataRepresentation()
        editor.canvas.setZoomScale(4, animated: false)
        scroll.alignBackground()
        XCTAssertEqual(editor.canvas.zoomScale, 4, accuracy: 0.01)
        XCTAssertTrue(editor.canvas.transform.isIdentity)
        XCTAssertEqual(paper.bounds.size, PageRenderer.size(try XCTUnwrap(editor.page)), "Zoom must keep tile coordinates stable")
        XCTAssertEqual(paper.frame.width, PageRenderer.size(try XCTUnwrap(editor.page)).width * 4, accuracy: 1)
        XCTAssertEqual(editor.canvas.drawing.dataRepresentation(), beforeZoom)
        editor.canvas.contentOffset = CGPoint(x: 120, y: 180)
        scroll.alignBackground()
        XCTAssertEqual(paper.frame.minX, -120, accuracy: 1)
        XCTAssertEqual(paper.frame.minY, -180, accuracy: 1)
        editor.selectedTool = .eraser
        host.rootView = WritingCanvas(session: editor, finger: false, reading: false)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(editor.canvas.tool is PKEraserTool)
        editor.selectedTool = .pen
        editor.inkWidth = 6
        host.rootView = WritingCanvas(session: editor, finger: false, reading: false)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual((editor.canvas.tool as? PKInkingTool)?.width, 6)
        XCTAssertTrue(editor.canvas.drawingGestureRecognizer.isEnabled)
        host.rootView = WritingCanvas(session: editor, finger: true, reading: true)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(editor.canvas.drawingPolicy, .anyInput)
        XCTAssertFalse(editor.canvas.drawingGestureRecognizer.isEnabled)
        let screenshot = UIGraphicsImageRenderer(bounds: host.view.bounds).image { context in host.view.layer.render(in: context.cgContext) }
        let attachment = XCTAttachment(image: screenshot); attachment.name = "Canvas lecture"; attachment.lifetime = .keepAlways; add(attachment)
        let zoomHost = UIHostingController(rootView: WritingCanvas(session: editor, finger: false, reading: false, zoomWindow: true))
        window.rootViewController = zoomHost
        zoomHost.loadViewIfNeeded(); zoomHost.view.frame = window.bounds; zoomHost.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 200_000_000)
        func findCanvasScroll(_ view: UIView) -> UIScrollView? {
            if let scroll = view as? UIScrollView, scroll.delegate is WritingCanvas.Coordinator { return scroll }
            return view.subviews.lazy.compactMap { findCanvasScroll($0) }.first
        }
        let zoomScroll = findCanvasScroll(zoomHost.view)
        XCTAssertEqual(try XCTUnwrap(zoomScroll).zoomScale, 2, accuracy: 0.01)
        window.isHidden = true
    }
    func testNativeZoomPreservesStrokeCoordinates() throws {
        let canvas = PKCanvasView()
        let view = PageScrollView(canvas: canvas)
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 600)
        view.pageSize = CGSize(width: 500, height: 700)
        let points = [CGPoint(x: 40, y: 50), CGPoint(x: 200, y: 220)].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index), size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        canvas.drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))])
        let original = canvas.drawing.dataRepresentation()
        view.layoutIfNeeded()
        for zoom: CGFloat in [1, 2, 4] {
            canvas.setZoomScale(zoom, animated: false)
            view.alignBackground()
            XCTAssertTrue(canvas.transform.isIdentity)
            XCTAssertEqual(canvas.contentSize.width, 500 * zoom, accuracy: 1)
            XCTAssertEqual(canvas.contentSize.height, 700 * zoom, accuracy: 1)
            XCTAssertEqual(canvas.drawing.dataRepresentation(), original)
        }
    }
    func testElementsAndRotatedPDFGeometry() async throws {
        let pageID = UUID(), noteID = UUID()
        var page = NotePage(id: pageID, noteID: noteID, index: 0, format: .a4Portrait, template: .blank, drawingResourceID: "page.drawing")
        page.width = 500; page.height = 700
        page.elements = [PageElement(kind: .rectangle, x: 30, y: 40, width: 200, height: 100), PageElement(kind: .text, text: "Typed note")]
        let image = PageRenderer.image(page, data: nil)
        XCTAssertEqual(image.size, CGSize(width: 500, height: 700))
        XCTAssertNotNil(image.pngData())
        let input = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 500, height: 700)).pdfData { ctx in ctx.beginPage(); UIColor.red.setFill(); UIRectFill(CGRect(x: 30, y: 40, width: 100, height: 80)) }
        let pdf = try XCTUnwrap(PDFDocument(data: data)); pdf.page(at: 0)?.rotation = 90
        XCTAssertTrue(pdf.write(to: input))
        let store = LibraryStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)); await store.load()
        let imported = await store.importFile(input)
        let id = try XCTUnwrap(imported)
        let rotated = try XCTUnwrap(store.library.firstPage(in: id))
        XCTAssertEqual(rotated.width, 700); XCTAssertEqual(rotated.height, 500)
        let original = try await store.disk.read(try XCTUnwrap(rotated.backgroundID))
        let background = PageRenderer.image(rotated, data: original)
        XCTAssertEqual(background.size, CGSize(width: 700, height: 500))
        let archive = try await store.archive(id)
        let output = input.deletingPathExtension().appendingPathExtension("annotated.pdf")
        try PageRenderer.export(archive, indices: 0...0, output: output)
        XCTAssertEqual(PDFDocument(url: output)?.page(at: 0)?.bounds(for: .mediaBox).size, background.size)
    }
}
