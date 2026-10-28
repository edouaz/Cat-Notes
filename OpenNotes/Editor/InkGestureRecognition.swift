import UIKit

enum InkGestureRecognition {
    static func isScribble(_ points: [CGPoint], over drawing: InkDrawing) -> Bool {
        guard points.count >= 12, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }), !drawing.strokes.isEmpty else { return false }
        var path: [CGPoint] = [points[0]]
        for point in points.dropFirst() where hypot(point.x - path.last!.x, point.y - path.last!.y) >= 3 { path.append(point) }
        // shortcut: very long scribbles stay ink; add a spatial crossing index if real captures need more.
        guard (10...2048).contains(path.count) else { return false }
        let box = bounds(path), diagonal = hypot(box.width, box.height)
        guard diagonal >= 12, min(box.width, box.height) >= 6 else { return false }
        let length = zip(path, path.dropFirst()).reduce(CGFloat.zero) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
        guard length / diagonal > 4 else { return false }
        var reversals = 0
        for index in 2..<path.count {
            let a = CGPoint(x: path[index - 1].x - path[index - 2].x, y: path[index - 1].y - path[index - 2].y)
            let b = CGPoint(x: path[index].x - path[index - 1].x, y: path[index].y - path[index - 1].y)
            if (a.x * b.x + a.y * b.y) / max(0.001, hypot(a.x, a.y) * hypot(b.x, b.y)) < -0.25 { reversals += 1 }
        }
        guard reversals >= 3 else { return false }
        var crossings = 0
        for i in 0..<(path.count - 3) {
            for j in (i + 2)..<(path.count - 1) where crosses(path[i], path[i + 1], path[j], path[j + 1]) { crossings += 1 }
            if crossings >= 3 { break }
        }
        // Precision takes precedence: an ordinary zigzag or signature must remain ink.
        guard crossings >= 3 || (reversals >= 6 && crossings >= 1) else { return false }
        return EraserEditing.erase(drawing, along: path, width: 8, mode: .stroke).strokes.count < drawing.strokes.count
    }

    static func circle(_ points: [CGPoint]) -> UIBezierPath? {
        guard points.count >= 16, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }), let first = points.first, let last = points.last else { return nil }
        let box = bounds(points), diagonal = hypot(box.width, box.height)
        guard min(box.width, box.height) >= 20, max(box.width, box.height) / min(box.width, box.height) < 2.2,
              hypot(first.x - last.x, first.y - last.y) < diagonal * 0.14 else { return nil }
        let radialError = points.reduce(CGFloat.zero) { $0 + abs(hypot(($1.x - box.midX) / (box.width / 2), ($1.y - box.midY) / (box.height / 2)) - 1) } / CGFloat(points.count)
        guard radialError < 0.10 else { return nil }
        var turning: CGFloat = 0, absoluteTurning: CGFloat = 0
        for pair in zip(points, points.dropFirst()) {
            var angle = atan2(pair.1.y - box.midY, pair.1.x - box.midX) - atan2(pair.0.y - box.midY, pair.0.x - box.midX)
            if angle > .pi { angle -= 2 * .pi }; if angle < -.pi { angle += 2 * .pi }
            turning += angle; absoluteTurning += abs(angle)
        }
        guard abs(turning) > 1.75 * .pi, abs(turning) < 2.25 * .pi, absoluteTurning < 2.6 * .pi else { return nil }
        let result = UIBezierPath(); result.move(to: first)
        for point in points.dropFirst() { result.addLine(to: point) }
        result.close()
        return result
    }

    static func isOnContour(_ point: CGPoint, contour: [CGPoint], tolerance: CGFloat) -> Bool {
        point.x.isFinite && point.y.isFinite && tolerance.isFinite && tolerance >= 0 && EraserEditing.distance(point, to: contour) <= tolerance
    }

    private static func bounds(_ points: [CGPoint]) -> CGRect {
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    private static func crosses(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
        func side(_ a: CGPoint, _ b: CGPoint, _ p: CGPoint) -> CGFloat { (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x) }
        return side(a, b, c) * side(a, b, d) < 0 && side(c, d, a) * side(c, d, b) < 0
    }
}
