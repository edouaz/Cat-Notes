import XCTest
import UIKit
@testable import OpenNotes

final class NativeInkGestureTests: XCTestCase {
    private func stroke(_ points: [CGPoint], pressure: [CGFloat] = [], width: CGFloat = 4) -> InkStroke {
        let samples = points.enumerated().map { index, point in
            InkStrokePoint(location: point, timeOffset: Double(index) / 120,
                           size: CGSize(width: width, height: width), opacity: 1,
                           force: pressure.isEmpty ? 0.5 : pressure[index], azimuth: 0, altitude: .pi / 2)
        }
        return InkStroke(ink: InkInk(.pen, color: .blue), path: InkStrokePath(controlPoints: samples, creationDate: Date(timeIntervalSince1970: 0)))
    }

    func testBallIgnoresPressureAndOtherProfilesVaryWhileRawSamplesStayExact() throws {
        let source = stroke((0...20).map { CGPoint(x: $0 * 4, y: 20) }, pressure: (0...20).map { CGFloat($0) / 20 })
        var settings = EditorToolSettings()
        settings.pressureEnabled = true
        settings.tipSharpness = 1
        let ball = try XCTUnwrap(StrokeProcessing.process(source, tool: .pen, width: 8, settings: settings, shapeHeld: false))
        XCTAssertEqual(ball.style?.sharpness, 0)
        XCTAssertTrue(ball.path.allSatisfy { $0.size == CGSize(width: 8, height: 8) })
        var profiles: [CGFloat] = []
        for kind in [EditorToolSettings.PenStyle.fountain, .brush] {
            settings.penStyle = kind
            let result = try XCTUnwrap(StrokeProcessing.process(source, tool: .pen, width: 8, settings: settings, shapeHeld: false))
            XCTAssertLessThan(result.path.first!.size.width, result.path.last!.size.width)
            XCTAssertEqual(result.rawSamples.map(\.location), source.path.map(\.location))
            XCTAssertEqual(result.rawSamples.map(\.force), source.path.map(\.force))
            profiles.append(result.path.last!.size.width - result.path.first!.size.width)
        }
        XCTAssertGreaterThan(profiles[1], profiles[0])
    }

    func testPartialEraseCreatesIndependentFragmentsAndKeepsSeparateDot() throws {
        let line = stroke([CGPoint(x: 10, y: 50), CGPoint(x: 150, y: 50)])
        let dot = stroke([CGPoint(x: 80, y: 25)])
        let original = InkDrawing(strokes: [line, dot])
        let erased = EraserEditing.erase(original, along: [CGPoint(x: 80, y: 40), CGPoint(x: 80, y: 60)], width: 10, mode: .pixel)
        XCTAssertEqual(erased.strokes.count, 3)
        XCTAssertEqual(erased.strokes.last?.id, dot.id)
        let pieces = Array(erased.strokes.dropLast())
        XCTAssertTrue(pieces.allSatisfy { $0.id != line.id })
        XCTAssertNotEqual(pieces[0].id, pieces[1].id)
        XCTAssertLessThan(pieces[0].path.last!.location.x, 80)
        XCTAssertGreaterThan(pieces[1].path.first!.location.x, 80)
        let reopened = try InkDrawing(data: erased.dataRepresentation())
        XCTAssertEqual(reopened.dataRepresentation(), erased.dataRepresentation())
        XCTAssertEqual(original.strokes[0].id, line.id)
        XCTAssertEqual(original.strokes[0].path.count, 2)
    }

    func testEraserDoesNotHitPatternGapsOrBoundingBoxOnly() throws {
        var dashed = stroke([CGPoint(x: 0, y: 50), CGPoint(x: 100, y: 50)])
        dashed.style = InkStyle(kind: .ballpoint, width: 4, pattern: .dashed)
        let drawing = InkDrawing(strokes: [dashed])
        let gap = EraserEditing.erase(drawing, along: [CGPoint(x: 16, y: 50)], width: 1, mode: .stroke)
        XCTAssertEqual(gap.dataRepresentation(), drawing.dataRepresentation())
        XCTAssertTrue(EraserEditing.erase(drawing, along: [CGPoint(x: 6, y: 50)], width: 1, mode: .stroke).strokes.isEmpty)
        let diagonal = stroke([.zero, CGPoint(x: 100, y: 100)])
        let remote = InkDrawing(strokes: [diagonal])
        XCTAssertEqual(EraserEditing.erase(remote, along: [CGPoint(x: 10, y: 90)], width: 5, mode: .pixel).dataRepresentation(), remote.dataRepresentation())
    }

    func testScribbleNeedsRepetitionCrossingsAndActualInkOverlap() {
        let points = [CGPoint(x: 20, y: 30), CGPoint(x: 140, y: 80), CGPoint(x: 25, y: 75), CGPoint(x: 135, y: 25),
                      CGPoint(x: 30, y: 30), CGPoint(x: 130, y: 80), CGPoint(x: 35, y: 75), CGPoint(x: 125, y: 25),
                      CGPoint(x: 40, y: 30), CGPoint(x: 120, y: 80), CGPoint(x: 45, y: 75), CGPoint(x: 115, y: 25), CGPoint(x: 50, y: 30)]
        let ink = InkDrawing(strokes: [stroke([CGPoint(x: 10, y: 50), CGPoint(x: 150, y: 50)])])
        XCTAssertTrue(InkGestureRecognition.isScribble(points, over: ink))
        XCTAssertFalse(InkGestureRecognition.isScribble(points, over: InkDrawing()))
        let handwriting = (0...30).map { CGPoint(x: $0 * 4, y: $0.isMultiple(of: 2) ? 30 : 70) }
        XCTAssertFalse(InkGestureRecognition.isScribble(handwriting, over: ink))
        XCTAssertFalse(InkGestureRecognition.isScribble(points.map { CGPoint(x: $0.x + 300, y: $0.y) }, over: ink))
    }

    func testCircleCandidateRequiresClosedRoundContourAndContourHit() throws {
        let circle = (0...64).map { index in
            let angle = CGFloat(index) * 2 * .pi / 64
            return CGPoint(x: 100 + 50 * cos(angle), y: 100 + 50 * sin(angle))
        }
        XCTAssertNotNil(InkGestureRecognition.circle(circle))
        XCTAssertNil(InkGestureRecognition.circle(Array(circle.prefix(40))))
        XCTAssertNil(InkGestureRecognition.circle([.zero, CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100), .zero]))
        XCTAssertTrue(InkGestureRecognition.isOnContour(CGPoint(x: 150, y: 100), contour: circle, tolerance: 4))
        XCTAssertFalse(InkGestureRecognition.isOnContour(CGPoint(x: 100, y: 100), contour: circle, tolerance: 4))
    }

    func testPolygonAndSmoothCurveRecognitionRemainConservative() throws {
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 50, y: 90), .zero]
        var triangle: [CGPoint] = []
        for edge in 0..<3 {
            let a = corners[edge], b = corners[edge + 1]
            for index in 0..<16 {
                let t = CGFloat(index) / 16
                let x = a.x + (b.x - a.x) * t
                let y = a.y + (b.y - a.y) * t
                triangle.append(CGPoint(x: x, y: y))
            }
        }
        triangle.append(.zero)
        XCTAssertEqual(ShapeRecognition.recognize(triangle)?.count, 4)
        let curve = (0...48).map { index in
            let t = CGFloat(index) / 48
            return CGPoint(x: 200 * t, y: 160 * t * (1 - t))
        }
        XCTAssertNotNil(ShapeRecognition.recognize(curve))
        XCTAssertNil(ShapeRecognition.recognize([.zero, CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 0)]))
    }
}
