import XCTest
import PencilKit
import SwiftUI
@testable import CatNotes

@MainActor
final class ToolSettingsTests: XCTestCase {
    func testPreferencesKeepToolLayoutFavoritesAndEraserSizeAcrossModesAndReopen() async throws {
        let name = UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        preferences.set("#202725,#B34242,#315BB1", forKey: "favoriteInkColors")
        let store = LibraryStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(name))
        await store.load()
        let session = EditorSession(store: store, noteID: UUID(), preferences: preferences)
        XCTAssertEqual(session.toolSettings.colors(for: .pen).count, 3)
        XCTAssertEqual(session.toolSettings.colors(for: .marker).count, 6)
        session.selectedTool = .marker; session.setFavoriteColors(["#FF0000", "#00FF00", "#0000FF", "#FFFF00"])
        session.toolSettings.toolbarOrder.reverse()
        session.toolSettings.hiddenTools.insert(.marker)
        session.toolSettings.eraserWidth = 57
        for mode in EditorToolSettings.EraserMode.allCases { session.toolSettings.eraserMode = mode; XCTAssertEqual(session.toolSettings.eraserWidth, 57) }
        session.toolSettings.lassoShape = .rectangle; session.toolSettings.includeImages = false
        session.toolSettings.penStyle = .brush; session.toolSettings.stabilization = 72
        let reopened = EditorSession(store: store, noteID: session.noteID, preferences: preferences)
        XCTAssertEqual(session.toolSettings, reopened.toolSettings)
        XCTAssertEqual(reopened.toolSettings.colors(for: .pen).first, "#202725")
        XCTAssertEqual(reopened.toolSettings.colors(for: .marker).first, "#FF0000")
    }

    func testEraserMasksPixelsPreservesTransformAndWholeStrokeModes() throws {
        let samples = stride(from: 10.0, through: 190.0, by: 2).map { x in
            PKStrokePoint(location: CGPoint(x: x, y: 60), timeOffset: x / 100, size: CGSize(width: 8, height: 8), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let stroke = PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: samples, creationDate: Date()), transform: CGAffineTransform(translationX: 20, y: 10), mask: nil)
        let drawing = PKDrawing(strokes: [stroke])
        let path = [CGPoint(x: 120, y: 50), CGPoint(x: 120, y: 90)]
        let pixel = EraserEditing.erase(drawing, along: path, width: 20, mode: .pixel)
        let clipped = try XCTUnwrap(pixel.strokes.first)
        XCTAssertEqual(clipped.path.count, stroke.path.count)
        XCTAssertEqual(clipped.transform, stroke.transform)
        XCTAssertFalse(try XCTUnwrap(clipped.mask).contains(CGPoint(x: 100, y: 60)))
        XCTAssertTrue(try XCTUnwrap(clipped.mask).contains(CGPoint(x: 30, y: 60)))
        let decoded = try PKDrawing(data: pixel.dataRepresentation())
        XCTAssertNotNil(decoded.strokes.first?.mask)
        let rect = CGRect(x: 0, y: 0, width: 240, height: 140)
        let beforeImage = drawing.image(from: rect, scale: 1)
        let erasedImage = pixel.image(from: rect, scale: 1)
        let reopenedImage = decoded.image(from: rect, scale: 1)
        XCTAssertGreaterThan(try alpha(beforeImage, at: CGPoint(x: 120, y: 70)), 200)
        XCTAssertLessThan(try alpha(erasedImage, at: CGPoint(x: 120, y: 70)), 10, "The erased pixels must actually disappear in PencilKit's renderer")
        XCTAssertGreaterThan(try alpha(erasedImage, at: CGPoint(x: 50, y: 70)), 200)
        XCTAssertLessThan(try alpha(reopenedImage, at: CGPoint(x: 120, y: 70)), 10)
        XCTAssertGreaterThan(try alpha(reopenedImage, at: CGPoint(x: 50, y: 70)), 200)
        XCTAssertTrue(EraserEditing.erase(drawing, along: path, width: 20, mode: .stroke).strokes.isEmpty)
        XCTAssertEqual(EraserEditing.erase(drawing, along: path, width: 20, mode: .intelligent).strokes.count, 1)
        XCTAssertTrue(EraserEditing.erase(drawing, along: path, width: 240, mode: .intelligent).strokes.isEmpty)
        let remote = EraserEditing.erase(drawing, along: [CGPoint(x: 400, y: 400)], width: 20, mode: .pixel)
        XCTAssertNil(remote.strokes.first?.mask)
        // Repeated overlapping erasures must subtract, never restore the first hole.
        let second = EraserEditing.erase(pixel, along: [CGPoint(x: 170, y: 70)], width: 16, mode: .pixel)
        XCTAssertFalse(try XCTUnwrap(second.strokes.first?.mask).contains(CGPoint(x: 100, y: 60)))
    }

    func testEraserCanRemoveVisibleFringeAfterCenterlineWasErased() throws {
        let points = stride(from: 20.0, through: 180.0, by: 2).map { x in
            PKStrokePoint(location: CGPoint(x: x, y: 70), timeOffset: x / 100, size: CGSize(width: 20, height: 20), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))])
        let split = EraserEditing.erase(drawing, along: [CGPoint(x: 0, y: 70), CGPoint(x: 200, y: 70)], width: 8, mode: .pixel)
        XCTAssertFalse(try XCTUnwrap(split.strokes.first?.mask).contains(CGPoint(x: 100, y: 70)))
        let rect = CGRect(x: 0, y: 0, width: 200, height: 140)
        XCTAssertGreaterThan(try alpha(split.image(from: rect, scale: 1), at: CGPoint(x: 100, y: 63)), 10)
        let erased = EraserEditing.erase(split, along: [CGPoint(x: 100, y: 63)], width: 10, mode: .pixel)
        XCTAssertLessThan(try alpha(erased.image(from: rect, scale: 1), at: CGPoint(x: 100, y: 63)), 10)
        XCTAssertGreaterThan(try alpha(erased.image(from: rect, scale: 1), at: CGPoint(x: 100, y: 77)), 10)
    }

    func testBatchElementActionRejectsInvalidAndDuplicateObjects() throws {
        let page = NotePage(noteID: UUID(), index: 0, format: .a4Portrait, template: .blank, drawingResourceID: "ink.drawing")
        var note = PageElement(kind: .stickyNote, text: "Texte conservé")
        note.x = 20; note.y = 20; note.width = 100; note.height = 100
        XCTAssertEqual(try DocumentAction(pageID: page.id, kind: .setElements, elements: [note]).applying(to: page).elements, [note])
        XCTAssertThrowsError(try DocumentAction(pageID: page.id, kind: .setElements, elements: [note, note]).applying(to: page))
        note.x = -1
        XCTAssertThrowsError(try DocumentAction(pageID: page.id, kind: .setElements, elements: [note]).applying(to: page))
    }

    private func alpha(_ image: UIImage, at point: CGPoint) throws -> UInt8 {
        let source = try XCTUnwrap(image.cgImage?.cropping(to: CGRect(origin: point, size: CGSize(width: 1, height: 1))))
        var pixel = [UInt8](repeating: 0, count: 4)
        return try pixel.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                                 space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(source, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return bytes[3]
        }
    }
}
