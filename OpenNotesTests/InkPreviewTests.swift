import XCTest
import PencilKit
import SwiftUI
@testable import OpenNotes

@MainActor
final class InkPreviewTests: XCTestCase {
    private func withSession(_ body: (EditorSession) throws -> Void) throws {
        let name = "InkPreviewTests-" + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        let store = LibraryStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(name))
        try body(EditorSession(store: store, noteID: UUID(), preferences: preferences))
    }

    func testSelectableWidthsAreTheActualWidthsAfterReopen() throws {
        try withSession { session in
            for tool in [DrawingToolKind.pen, .pencil, .marker] {
                session.selectedTool = tool
                let range = session.documentInkWidthRange
                for requested in [range.lowerBound, (range.lowerBound + range.upperBound) / 2, range.upperBound] {
                    session.setDocumentInkWidth(requested)
                    XCTAssertEqual(session.documentInkWidth, requested, accuracy: 0.001)
                    XCTAssertEqual(try XCTUnwrap(InkPreviewSample(session: session)).processingWidth, requested, accuracy: 0.001)
                }
            }
        }
    }
    func testPreviewUsesActualToolWidthAndSamplePressure() throws {
        try withSession { session in
            session.selectedTool = .pen; session.inkWidth = 8
            let pen = try XCTUnwrap(InkPreviewSample(session: session))
            XCTAssertEqual(pen.inkWidth, try XCTUnwrap(session.tool as? PKInkingTool).width)
            XCTAssertTrue(try XCTUnwrap(pen.drawing().strokes.first).path.allSatisfy { $0.size.width == 8 })
            session.selectedTool = .marker; session.inkWidth = 8
            let marker = try XCTUnwrap(InkPreviewSample(session: session))
            XCTAssertEqual(marker.inkWidth, 32)
            let path = try XCTUnwrap(marker.drawing().strokes.first).path
            XCTAssertTrue(path.allSatisfy { $0.size.width == marker.inkWidth })
            XCTAssertLessThan(try XCTUnwrap(path.first).force, path[40].force)
            session.selectedTool = .eraser
            XCTAssertNil(InkPreviewSample(session: session))
        }
    }

    func testPreviewRespondsToWidthColorAndSameCanvasStyleProcessing() throws {
        try withSession { session in
            session.selectedTool = .pen; session.inkWidth = 4; session.inkColor = .red
            session.toolSettings.penStyle = .ballpoint
            let red = try XCTUnwrap(InkPreviewSample(session: session))
            session.inkColor = .blue
            let blue = try XCTUnwrap(InkPreviewSample(session: session))
            XCTAssertNotEqual(red, blue)
            XCTAssertEqual(blue.drawing().strokes.first?.ink.color.presetHex, blue.color.presetHex)
            XCTAssertNotEqual(try XCTUnwrap(red.render()).pngData(), try XCTUnwrap(blue.render()).pngData())
            session.inkWidth = 12
            let wide = try XCTUnwrap(InkPreviewSample(session: session))
            XCTAssertNotEqual(blue, wide)
            XCTAssertEqual(wide.drawing().strokes.first?.path.first?.size.width, 12)
            session.toolSettings.penStyle = .fountain
            let fountain = try XCTUnwrap(InkPreviewSample(session: session))
            let path = try XCTUnwrap(fountain.drawing().strokes.first).path
            XCTAssertLessThan(path[40].size.height, path[40].size.width)
            session.toolSettings.penStyle = .brush
            let brush = try XCTUnwrap(InkPreviewSample(session: session))
            XCTAssertNotEqual(fountain, brush)
            XCTAssertNotEqual(fountain.drawing().dataRepresentation(), brush.drawing().dataRepresentation())
        }
    }

    func testImageKeepsDocumentPointScaleAtEngineLimit() throws {
        try withSession { session in
            session.selectedTool = .marker; session.inkWidth = 32
            let sample = try XCTUnwrap(InkPreviewSample(session: session))
            XCTAssertEqual(sample.inkWidth, try XCTUnwrap(session.tool as? PKInkingTool).width)
            XCTAssertLessThanOrEqual(sample.inkWidth, 128)
            let image = try XCTUnwrap(sample.render())
            XCTAssertEqual(image.size, InkPreviewSample.size)
            XCTAssertEqual(image.scale, 2)
            XCTAssertEqual(image.cgImage?.width, Int(InkPreviewSample.size.width * 2))
            XCTAssertLessThanOrEqual(sample.drawing().bounds.maxY, InkPreviewSample.size.height)
            XCTAssertGreaterThanOrEqual(sample.drawing().bounds.minY, 0)
        }
    }
    func testMarkerSwatchUsesPaperAppearanceAndTracksColor() throws {
        var light: UIImage!, dark: UIImage!
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            light = InkPreviewSample.markerSwatch(color: .yellow)
        }
        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
            dark = InkPreviewSample.markerSwatch(color: .yellow)
        }
        XCTAssertEqual(light.pngData(), dark.pngData())
        XCTAssertEqual(light.size, CGSize(width: 24, height: 24))
        XCTAssertNotEqual(light.pngData(), InkPreviewSample.markerSwatch(color: .blue).pngData())
    }

}
