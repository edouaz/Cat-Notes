import XCTest
import UIKit
@testable import OpenNotes

@MainActor
final class EraserGeometryTests: XCTestCase {
    private func line(width: CGFloat = 40, kind: InkInk.InkType = .pen) -> InkStroke {
        let points = [CGPoint(x: 20, y: 100), CGPoint(x: 220, y: 100)].enumerated().map {
            InkStrokePoint(location: $0.element, timeOffset: Double($0.offset), size: CGSize(width: width, height: width), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return InkStroke(ink: InkInk(kind, color: .black), path: InkStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 0)))
    }
    func testPrecisionPreservesLateralInkAndRoundTripsWithoutRestoringHole() throws {
        let source = line()
        let erased = EraserEditing.erase(InkDrawing(strokes: [source]), along: [CGPoint(x: 100, y: 100)], width: 10, mode: .precision)
        let stroke = try XCTUnwrap(erased.strokes.first)
        XCTAssertEqual(stroke.id, source.id)
        XCTAssertFalse(stroke.paintedPath.contains(CGPoint(x: 100, y: 100)))
        XCTAssertTrue(stroke.paintedPath.contains(CGPoint(x: 100, y: 115)))
        XCTAssertEqual(stroke.rawSamples, source.rawSamples)
        let bytes = try erased.encodedData()
        let reopened = try InkDrawing(data: bytes)
        XCTAssertFalse(reopened.strokes[0].paintedPath.contains(CGPoint(x: 100, y: 100)))
        XCTAssertEqual(try reopened.encodedData(), bytes)
        let repeated = EraserEditing.erase(reopened, along: [CGPoint(x: 130, y: 100)], width: 10, mode: .precision)
        XCTAssertFalse(repeated.strokes[0].paintedPath.contains(CGPoint(x: 100, y: 100)))
        XCTAssertFalse(repeated.strokes[0].paintedPath.contains(CGPoint(x: 130, y: 100)))
    }
    func testModesFilterAndFastSweepAreDistinct() throws {
        let source = line()
        let drawing = InkDrawing(strokes: [source])
        let path = [CGPoint(x: 100, y: 30), CGPoint(x: 100, y: 170)]
        XCTAssertTrue(EraserEditing.erase(drawing, along: path, width: 10, mode: .stroke).strokes.isEmpty)
        let standard = EraserEditing.erase(drawing, along: path, width: 10, mode: .standard)
        XCTAssertEqual(standard.strokes.count, 2)
        let precision = EraserEditing.erase(drawing, along: path, width: 10, mode: .precision)
        XCTAssertEqual(precision.strokes.count, 1)
        XCTAssertFalse(precision.strokes[0].paintedPath.contains(CGPoint(x: 100, y: 100)))
        XCTAssertEqual(EraserEditing.erase(drawing, along: path, width: 10, mode: .stroke, erasePen: false).strokes.count, 1)
        let marker = InkDrawing(strokes: [line(kind: .marker)])
        XCTAssertEqual(EraserEditing.erase(marker, along: path, width: 10, mode: .stroke, eraseHighlighter: false).strokes.count, 1)
    }
    func testPrecisionLocalCoordinatesSurviveRotationAndStandardDoesNotRestoreMask() throws {
        var source = line()
        source.transform = CGAffineTransform(rotationAngle: .pi / 2).concatenating(CGAffineTransform(translationX: 200, y: 0))
        let result = EraserEditing.erase(InkDrawing(strokes: [source]), along: [CGPoint(x: 100, y: 100)], width: 10, mode: .precision)
        XCTAssertFalse(try XCTUnwrap(result.strokes.first).paintedPath.contains(CGPoint(x: 100, y: 100)))
        let split = EraserEditing.erase(result, along: [CGPoint(x: 100, y: 150)], width: 12, mode: .standard)
        XCTAssertFalse(split.strokes.contains { $0.paintedPath.contains(CGPoint(x: 100, y: 100)) })
    }
    func testSchemaOneBackupBeforeFirstWrite() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = DiskStore(root: root)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: InkDrawing(strokes: [line()]).encodedData()) as? [String: Any])
        object["inkSchemaVersion"] = 1
        let old = try JSONSerialization.data(withJSONObject: object)
        try await disk.write(old, name: "old.drawing")
        let latest = try InkDrawing(data: old).encodedData()
        try await disk.write(latest, name: "old.drawing")
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("ink-schema-backups/old.drawing")), old)
        let current = try await disk.read("old.drawing")
        XCTAssertEqual(current, latest)
    }
    func testSpatialIndexAndInvalidInput() throws {
        let stroke = line()
        let drawing = InkDrawing(strokes: [stroke])
        let index = InkSpatialIndex(drawing)
        XCTAssertTrue(index.query(CGRect(x: 100, y: 90, width: 10, height: 10)).contains(stroke.id))
        XCTAssertFalse(index.query(CGRect(x: 500, y: 500, width: 10, height: 10)).contains(stroke.id))
        XCTAssertEqual(try EraserEditing.erase(drawing, along: [CGPoint(x: CGFloat.nan, y: 0)], width: 10, mode: .precision).encodedData(), try drawing.encodedData())
    }
}
