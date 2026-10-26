import XCTest
import PencilKit
@testable import OpenNotes

@MainActor
final class InkPipelineTests: XCTestCase {
    private func stroke(transform: CGAffineTransform = .identity) -> PKStroke {
        let samples = [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 13), CGPoint(x: 90, y: 8)]
        let times = [0.0, 0.017, 0.2]
        let points = samples.enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: times[index], size: CGSize(width: 3, height: 3), opacity: 1,
                          force: CGFloat(index + 1) / 4, azimuth: 0.4, altitude: 1)
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()), transform: transform, mask: nil)
    }
    func testProcessingKeepsActualSampleTimesAndPressure() throws {
        let source = stroke()
        let result = try XCTUnwrap(StrokeProcessing.process(source, tool: .pen, width: 3, settings: EditorToolSettings(), shapeHeld: false))
        for index in 0..<source.path.count {
            XCTAssertEqual(result.path[index].timeOffset, source.path[index].timeOffset)
            XCTAssertEqual(result.path[index].force, source.path[index].force)
        }
        let reopened = try PKDrawing(data: PKDrawing(strokes: [result]).dataRepresentation())
        XCTAssertEqual(reopened.strokes.first?.path.count, source.path.count)
    }
    func testRecognitionUsesPageScaleAndRejectsNonfinitePoints() {
        let logical = [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 10), CGPoint(x: 90, y: 10)]
        for zoom: CGFloat in [0.1, 0.5, 1, 4] {
            let screen = logical.map { CGPoint(x: $0.x * zoom, y: $0.y * zoom) }
            XCTAssertEqual(CanvasTouchObserver.recognizeScreenPoints(screen, zoom: zoom), [logical[0], logical[2]])
        }
        XCTAssertNil(CanvasTouchObserver.recognizeScreenPoints(logical, zoom: 0))
        XCTAssertNil(ShapeRecognition.recognize([.zero, CGPoint(x: CGFloat.nan, y: 1)]))
    }
    func testFingerShapeObservationFollowsDrawingPolicy() {
        let observer = CanvasTouchObserver()
        XCTAssertTrue(observer.accepts(.pencil)); XCTAssertFalse(observer.accepts(.direct))
        observer.fingerDrawing = true
        XCTAssertTrue(observer.accepts(.direct)); XCTAssertFalse(observer.accepts(.indirectPointer))
    }
    func testRecoveredIntervalAndPressureProfiles() throws {
        XCTAssertNil(StrokeProcessing.stabilizationInterval(0))
        XCTAssertNil(StrokeProcessing.stabilizationInterval(.nan))
        XCTAssertEqual(try XCTUnwrap(StrokeProcessing.stabilizationInterval(0.5)), 0.04, accuracy: 1e-12)
        XCTAssertEqual(StrokeProcessing.stabilizationInterval(2), StrokeProcessing.stabilizationInterval(1))
        var settings = EditorToolSettings(); settings.penStyle = .brush
        settings.pressureSensitivity = 0
        let insensitive = try XCTUnwrap(StrokeProcessing.process(stroke(), tool: .pen, width: 3, settings: settings, shapeHeld: false))
        settings.pressureSensitivity = 1
        let sensitive = try XCTUnwrap(StrokeProcessing.process(stroke(), tool: .pen, width: 3, settings: settings, shapeHeld: false))
        XCTAssertLessThan(sensitive.path[1].size.width, insensitive.path[1].size.width)
        settings.stabilization = 0; settings.stabilizationByStyle = ["brush": 100]
        XCTAssertEqual(settings.stabilization(for: .pen), 100)
    }
    func testNativeRulerDoesNotConvertHeldMarkerIntoShape() {
        var settings = EditorToolSettings(); settings.rulerEnabled = true
        XCTAssertNil(StrokeProcessing.process(stroke(), tool: .marker, width: 3, settings: settings, shapeHeld: true))
    }
}
