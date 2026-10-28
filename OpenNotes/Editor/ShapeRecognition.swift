import Foundation
import PencilKit

// Conservative, explicit recognition: ambiguous strokes remain unchanged.
enum ShapeRecognition {
    struct Adjustment {
        private let original: [CGPoint]
        private let initialPointer: CGPoint

        init(points: [CGPoint], pointer: CGPoint) {
            original = points
            initialPointer = pointer
        }

        func points(at pointer: CGPoint) -> [CGPoint] {
            guard original.count >= 2,
                  (original + [initialPointer, pointer]).allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return original }
            if original.count == 2 {
                let end = CGPoint(x: original[1].x + pointer.x - initialPointer.x,
                                  y: original[1].y + pointer.y - initialPointer.y)
                return end.x.isFinite && end.y.isFinite ? [original[0], end] : original
            }
            let xs = original.map(\.x), ys = original.map(\.y)
            let center = CGPoint(x: (xs.min()! + xs.max()!) / 2, y: (ys.min()! + ys.max()!) / 2)
            let initial = CGPoint(x: initialPointer.x - center.x, y: initialPointer.y - center.y)
            let current = CGPoint(x: pointer.x - center.x, y: pointer.y - center.y)
            let length = hypot(initial.x, initial.y)
            guard length > 1, hypot(current.x, current.y) > 1 else { return original }
            let scale = hypot(current.x, current.y) / length
            let angle = atan2(current.y, current.x) - atan2(initial.y, initial.x)
            let result = original.map { point in
                let x = point.x - center.x, y = point.y - center.y
                return CGPoint(x: center.x + scale * (x * cos(angle) - y * sin(angle)),
                               y: center.y + scale * (x * sin(angle) + y * cos(angle)))
            }
            return result.allSatisfy { $0.x.isFinite && $0.y.isFinite } ? result : original
        }
    }

    static func recognize(_ points: [CGPoint]) -> [CGPoint]? {
        guard points.count >= 2, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }), let first = points.first, let last = points.last else { return nil }
        let xs = points.map(\.x), ys = points.map(\.y)
        let bounds = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        let diagonal = hypot(bounds.width, bounds.height)
        guard diagonal > 20 else { return nil }
        let distance = hypot(last.x - first.x, last.y - first.y)
        if distance > diagonal * 0.85 {
            let deviation = points.map { abs((last.y - first.y) * $0.x - (last.x - first.x) * $0.y + last.x * first.y - last.y * first.x) / distance }.max()!
            if deviation < max(3, diagonal * 0.06) { return [first, last] }
            return nil
        }
        guard distance < diagonal * 0.15, bounds.width > 20, bounds.height > 20, points.count > 8 else { return nil }
        let ellipseError = points.map { abs(hypot(($0.x - bounds.midX) / (bounds.width / 2), ($0.y - bounds.midY) / (bounds.height / 2)) - 1) }.reduce(0, +) / Double(points.count)
        if ellipseError < 0.1 {
            return (0...64).map { i in let angle = Double(i) / 64 * 2 * Double.pi; return CGPoint(x: bounds.midX + cos(angle) * bounds.width / 2, y: bounds.midY + sin(angle) * bounds.height / 2) }
        }
        // Fit a rectangle independently of its orientation, including hand-drawn corners.
        var rectangle: [CGPoint]?
        var bestError = diagonal * 0.025
        for step in 0..<30 {
            let angle = CGFloat(step) * .pi / 60
            let rotation = CGAffineTransform(rotationAngle: -angle)
            let rotated = points.map { $0.applying(rotation) }
            let xs = rotated.map(\.x), ys = rotated.map(\.y)
            let box = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
            guard box.width > 20, box.height > 20 else { continue }
            let corners = [box.origin, CGPoint(x: box.maxX, y: box.minY), CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
            let edgeError = rotated.map { min(abs($0.x - box.minX), abs($0.x - box.maxX), abs($0.y - box.minY), abs($0.y - box.maxY)) }.reduce(0, +) / Double(points.count)
            let coversCorners = corners.allSatisfy { corner in rotated.contains { hypot($0.x - corner.x, $0.y - corner.y) < diagonal * 0.12 } }
            if edgeError < bestError && coversCorners {
                bestError = edgeError
                rectangle = (corners + [corners[0]]).map { $0.applying(rotation.inverted()) }
            }
        }
        return rectangle
    }
}
@MainActor
extension EditorSession {
    func recognizeShape() {
        let drawing = canvas.drawing
        guard let last = drawing.strokes.last,
              let points = ShapeRecognition.recognize(last.path.map { $0.location.applying(last.transform) }) else {
            error = "Ambiguous stroke: draw a line, rectangle or closed ellipse."; return
        }
        let controls = points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.01, size: last.path.first?.size ?? CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let replacement = PKStroke(ink: last.ink, path: PKStrokePath(controlPoints: controls, creationDate: Date()))
        replaceDrawing(PKDrawing(strokes: Array(drawing.strokes.dropLast()) + [replacement]), actionName: "Smooth stroke")
    }
}
