import Foundation
import PencilKit

// Conservative, explicit recognition: ambiguous strokes remain unchanged.
enum ShapeRecognition {
    static func recognize(_ points: [CGPoint]) -> [CGPoint]? {
        guard points.count >= 2, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }), let first = points.first, let last = points.last else { return nil }
        let xs = points.map(\.x), ys = points.map(\.y)
        let bounds = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        let diagonal = hypot(bounds.width, bounds.height)
        guard diagonal > 20 else { return nil }
        let distance = hypot(last.x - first.x, last.y - first.y)
        if distance > diagonal * 0.85 {
            let deviation = points.map { abs((last.y - first.y) * $0.x - (last.x - first.x) * $0.y + last.x * first.y - last.y * first.x) / distance }.max()!
            if deviation < diagonal * 0.04 { return [first, last] }
            return nil
        }
        guard distance < diagonal * 0.15, bounds.width > 20, bounds.height > 20, points.count > 8 else { return nil }
        let ellipseError = points.map { abs(hypot(($0.x - bounds.midX) / (bounds.width / 2), ($0.y - bounds.midY) / (bounds.height / 2)) - 1) }.reduce(0, +) / Double(points.count)
        if ellipseError < 0.1 {
            return (0...64).map { i in let angle = Double(i) / 64 * 2 * Double.pi; return CGPoint(x: bounds.midX + cos(angle) * bounds.width / 2, y: bounds.midY + sin(angle) * bounds.height / 2) }
        }
        let edgeError = points.map { min(abs($0.x - bounds.minX), abs($0.x - bounds.maxX), abs($0.y - bounds.minY), abs($0.y - bounds.maxY)) }.reduce(0, +) / Double(points.count)
        if edgeError < diagonal * 0.025 { return [bounds.origin, CGPoint(x: bounds.maxX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.maxY), CGPoint(x: bounds.minX, y: bounds.maxY), bounds.origin] }
        return nil
    }
}
@MainActor
extension EditorSession {
    func recognizeShape() {
        let drawing = canvas.drawing
        guard let last = drawing.strokes.last,
              let points = ShapeRecognition.recognize(last.path.map { $0.location.applying(last.transform) }) else {
            error = "Trait ambigu : dessinez une ligne, un rectangle ou une ellipse fermée."; return
        }
        let controls = points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.01, size: last.path.first?.size ?? CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let replacement = PKStroke(ink: last.ink, path: PKStrokePath(controlPoints: controls, creationDate: Date()))
        replaceDrawing(PKDrawing(strokes: Array(drawing.strokes.dropLast()) + [replacement]), actionName: "Régulariser le trait")
    }
}
