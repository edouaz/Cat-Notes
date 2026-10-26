import XCTest
import PencilKit
@testable import OpenNotes

@MainActor
final class GoodnotesAdaptationTests: XCTestCase {
    func testAngularSnapPreservesAnchorAndLeavesOtherAnglesAlone() {
        let start = CGPoint(x: 50, y: 70), nearHorizontal = CGPoint(x: 150, y: 73)
        let snapped = StrokeProcessing.snappedLine([start, nearHorizontal])
        XCTAssertEqual(snapped[0], start); XCTAssertEqual(snapped[1].y, start.y, accuracy: 0.001)
        let oblique = CGPoint(x: 150, y: 95)
        XCTAssertEqual(StrokeProcessing.snappedLine([start, oblique]), [start, oblique])
    }
    func testLegacySettingsAndTextDecodeWithSafeDefaults() throws {
        let encoder = JSONEncoder()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(EditorToolSettings())) as? [String: Any])
        for key in ["stabilizationByStyle", "pressureSensitivity", "rulerEnabled", "includeText"] { object.removeValue(forKey: key) }
        object["stabilization"] = 42
        var settings = try JSONDecoder().decode(EditorToolSettings.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(settings.stabilization(for: .pen), 42)
        settings.setStabilization(80, for: .pen)
        settings.penStyle = .brush
        XCTAssertEqual(settings.stabilization(for: .pen), 42)
        settings.setStabilization(12, for: .pen)
        XCTAssertEqual(settings.stabilization(for: .marker), 42)
        settings.penStyle = .ballpoint
        XCTAssertEqual(settings.stabilization(for: .pen), 80)
        let text = try JSONDecoder().decode(PageElement.self, from: encoder.encode(PageElement(kind: .text)))
        XCTAssertNil(text.textFontSize); XCTAssertNil(text.textColorHex)
    }

    func testShapeStyleRoundTripAndValidation() throws {
        let page = NotePage(noteID: UUID(), index: 0, format: .a4Portrait, template: .blank, drawingResourceID: "ink.drawing")
        var item = PageElement(kind: .ellipse, x: 30, y: 40, width: 100, height: 70)
        item.strokeWidth = 4; item.strokeColorHex = "#0000FF"; item.fillColorHex = "#FF0000"
        let updated = try DocumentAction(pageID: page.id, kind: .upsertElement, element: item).applying(to: page)
        XCTAssertEqual(try JSONDecoder().decode(NotePage.self, from: JSONEncoder().encode(updated)).elements, [item])
        let image = try XCTUnwrap(PageRenderer.image(updated, data: nil, scale: 1).cgImage)
        let crop = try XCTUnwrap(image.cropping(to: CGRect(x: 79, y: 74, width: 1, height: 1)))
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        XCTAssertGreaterThan(pixel[0], 250); XCTAssertLessThan(pixel[1], 5); XCTAssertLessThan(pixel[2], 5)
        item.strokeWidth = -1
        XCTAssertThrowsError(try DocumentAction(pageID: page.id, kind: .upsertElement, element: item).applying(to: page))
    }
    func testTextStyleValidationAndLassoFilter() throws {
        let page = NotePage(noteID: UUID(), index: 0, format: .a4Portrait, template: .blank, drawingResourceID: "ink.drawing")
        var item = PageElement(kind: .text, x: 10, y: 20, width: 100, height: 100, text: "Note")
        item.textFontSize = 32; item.textColorHex = "#315BB1"
        let updated = try DocumentAction(pageID: page.id, kind: .upsertElement, element: item).applying(to: page)
        let region = UIBezierPath(rect: CGRect(x: 0, y: 0, width: 200, height: 200))
        var settings = EditorToolSettings()
        XCTAssertEqual(DocumentClipboard.selectedElements(updated, inside: region, settings: settings), [item])
        settings.includeText = false
        XCTAssertTrue(DocumentClipboard.selectedElements(updated, inside: region, settings: settings).isEmpty)
        item.textFontSize = .infinity
        XCTAssertThrowsError(try DocumentAction(pageID: page.id, kind: .upsertElement, element: item).applying(to: page))
        item.textFontSize = 20; item.textColorHex = "invalid"
        XCTAssertThrowsError(try DocumentAction(pageID: page.id, kind: .upsertElement, element: item).applying(to: page))
    }

    func testLassoResizeAndDeletePersistWithoutChangingExcludedObjects() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(root: directory); await store.load()
        let created = await store.create(); let id = try XCTUnwrap(created)
        let preferences = try XCTUnwrap(UserDefaults(suiteName: directory.lastPathComponent))
        defer { preferences.removePersistentDomain(forName: directory.lastPathComponent) }
        let session = EditorSession(store: store, noteID: id, preferences: preferences); await session.open()
        let pageID = try XCTUnwrap(session.page?.id)
        let coordinator = WritingCanvas.Coordinator(session: session, zoomWindow: false)
        coordinator.pageID = pageID
        coordinator.canvasViewDidBeginUsingTool(session.canvas)
        let points = [CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 50)].enumerated().map {
            PKStrokePoint(location: $0.element, timeOffset: Double($0.offset), size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: 1)
        }
        session.canvas.drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))])
        coordinator.cancelStroke(restoringDrawing: true)
        XCTAssertTrue(session.canvas.drawing.strokes.isEmpty, "Cancelled gestures must restore the drawing before the stroke")
        let text = PageElement(kind: .text, x: 100, y: 100, width: 100, height: 60, text: "Resize")
        let sticky = PageElement(kind: .stickyNote, x: 120, y: 120, width: 100, height: 60)
        let applied = await session.apply(.init(pageID: pageID, kind: .setElements, elements: [text, sticky])); XCTAssertTrue(applied)
        session.toolSettings.includeStickyNotes = false
        let region = UIBezierPath(rect: CGRect(x: 50, y: 50, width: 220, height: 220))
        var result = await session.transformSelection(inside: region, scale: 1.1); XCTAssertTrue(result)
        let resized = try XCTUnwrap(session.page?.elements?.first)
        XCTAssertEqual(resized.width, 110, accuracy: 0.01)
        XCTAssertEqual(resized.textFontSize ?? 0, 22, accuracy: 0.01)
        XCTAssertEqual(session.page?.elements?.last, sticky)
        result = await session.transformSelection(inside: region, scale: .nan); XCTAssertFalse(result)
        result = await session.transformSelection(inside: region, scale: 1, deleting: true); XCTAssertTrue(result)
        let reopened = EditorSession(store: store, noteID: id, preferences: preferences); await reopened.open(pageID)
        XCTAssertEqual(reopened.page?.elements, [sticky])
    }
}
