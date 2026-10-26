import PencilKit
import UIKit

// PKStroke masks preserve the original ink and support a sized pixel eraser on iPadOS 16.0.
enum EraserEditing {
    static func erase(_ drawing: PKDrawing, along points: [CGPoint], width: Double, mode: EditorToolSettings.EraserMode) -> PKDrawing {
        guard let first = points.first, width.isFinite, width > 0,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return drawing }
        let sweep: CGPath
        if points.count == 1 {
            sweep = CGPath(ellipseIn: CGRect(x: first.x - width / 2, y: first.y - width / 2, width: width, height: width), transform: nil)
        } else {
            let center = CGMutablePath(); center.move(to: first)
            for point in points.dropFirst() { center.addLine(to: point) }
            sweep = center.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 1)
        }
        let strokes = drawing.strokes.compactMap { stroke -> PKStroke? in
            guard stroke.renderBounds.intersects(sweep.boundingBoxOfPath), hit(stroke, sweep: sweep, radius: width / 2) else { return stroke }
            if mode == .stroke || (mode == .intelligent && max(stroke.renderBounds.width, stroke.renderBounds.height) <= width) { return nil }
            var inverse = stroke.transform.inverted()
            guard let localSweep = sweep.copy(using: &inverse) else { return stroke }
            let originalMask = stroke.mask?.cgPath ?? CGPath(rect: stroke.renderBounds.applying(inverse).insetBy(dx: -2, dy: -2), transform: nil)
            let mask = originalMask.subtracting(localSweep, using: stroke.mask?.usesEvenOddFillRule == true ? .evenOdd : .winding)
            guard !mask.isEmpty else { return nil }
            return PKStroke(ink: stroke.ink, path: stroke.path, transform: stroke.transform, mask: UIBezierPath(cgPath: mask), randomSeed: stroke.randomSeed)
        }
        return PKDrawing(strokes: strokes)
    }

    private static func hit(_ stroke: PKStroke, sweep: CGPath, radius: CGFloat) -> Bool {
        stroke.path.interpolatedPoints(by: .distance(max(1, min(4, radius / 3)))).contains { sample in
            let ellipse = CGPath(ellipseIn: CGRect(x: sample.location.x - sample.size.width / 2,
                y: sample.location.y - sample.size.height / 2, width: sample.size.width, height: sample.size.height), transform: nil)
            let visible = stroke.mask.map { ellipse.intersection($0.cgPath, using: $0.usesEvenOddFillRule ? .evenOdd : .winding) } ?? ellipse
            var transform = stroke.transform
            return visible.copy(using: &transform)?.intersects(sweep) == true
        }
    }
}
