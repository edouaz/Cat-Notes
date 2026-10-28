import UIKit

enum EraserEditing {
    static func erase(_ drawing: InkDrawing, along points: [CGPoint], width: Double, mode: EditorToolSettings.EraserMode) -> InkDrawing {
        guard !points.isEmpty, width.isFinite, width > 0,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return drawing }
        let radius = CGFloat(width / 2)
        let sweep = CGMutablePath()
        sweep.move(to: points[0])
        for point in points.dropFirst() { sweep.addLine(to: point) }
        let area: CGPath = points.count == 1
            ? CGPath(ellipseIn: CGRect(x: points[0].x - radius, y: points[0].y - radius, width: width, height: width), transform: nil)
            : sweep.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 1)
        let strokes = drawing.strokes.flatMap { stroke -> [InkStroke] in
            guard stroke.renderBounds.intersects(area.boundingBoxOfPath) else { return [stroke] }
            var transform = stroke.transform
            guard let paint = stroke.paintedPath.copy(using: &transform), paint.intersects(area) else { return [stroke] }
            if mode == .stroke || (mode == .intelligent && max(stroke.renderBounds.width, stroke.renderBounds.height) <= width) { return [] }
            let scale = max(hypot(transform.a, transform.b), hypot(transform.c, transform.d))
            func erased(_ sample: InkStrokePoint) -> Bool {
                distance(sample.location.applying(transform), to: points) <= radius + max(sample.size.width, sample.size.height) * scale / 2
            }
            var fragments: [InkStroke] = []
            for piece in stroke.paintedPaths() {
                guard !piece.isEmpty else { continue }
                let path = InkStrokePath(controlPoints: piece, creationDate: stroke.path.creationDate)
                let samples = Array(path.interpolatedPoints(by: .distance(0.5)))
                guard let first = samples.first else { continue }
                var kept: [InkStrokePoint] = erased(first) ? [] : [first]
                func finish() {
                    guard !kept.isEmpty else { return }
                    var fragment = stroke
                    fragment.id = UUID()
                    fragment.path = InkStrokePath(controlPoints: kept, creationDate: stroke.path.creationDate)
                    fragment.rawSamples = kept
                    // Painted pieces already contain the original pattern and taper geometry.
                    if var style = fragment.style { style.pattern = .solid; style.sharpness = 0; fragment.style = style }
                    fragments.append(fragment)
                    kept = []
                }
                for pair in zip(samples, samples.dropFirst()) {
                    let beforeErased = erased(pair.0), afterErased = erased(pair.1)
                    if beforeErased != afterErased {
                        var low: CGFloat = 0, high: CGFloat = 1
                        for _ in 0..<12 {
                            let middle = (low + high) / 2
                            if erased(interpolate(pair.0, pair.1, middle)) == beforeErased { low = middle } else { high = middle }
                        }
                        let boundary = interpolate(pair.0, pair.1, beforeErased ? high : low)
                        if beforeErased { kept = [boundary, pair.1] }
                        else { kept.append(boundary); finish() }
                    } else if !afterErased { kept.append(pair.1) }
                }
                finish()
            }
            return fragments
        }
        return InkDrawing(strokes: strokes)
    }

    static func interpolate(_ a: InkStrokePoint, _ b: InkStrokePoint, _ t: CGFloat) -> InkStrokePoint {
        InkStrokePoint(location: CGPoint(x: a.location.x + (b.location.x - a.location.x) * t, y: a.location.y + (b.location.y - a.location.y) * t),
                       timeOffset: a.timeOffset + (b.timeOffset - a.timeOffset) * Double(t),
                       size: CGSize(width: a.size.width + (b.size.width - a.size.width) * t, height: a.size.height + (b.size.height - a.size.height) * t),
                       opacity: a.opacity + (b.opacity - a.opacity) * t, force: a.force + (b.force - a.force) * t,
                       azimuth: a.azimuth + (b.azimuth - a.azimuth) * t, altitude: a.altitude + (b.altitude - a.altitude) * t)
    }

    static func distance(_ point: CGPoint, to path: [CGPoint]) -> CGFloat {
        guard let first = path.first else { return .infinity }
        var nearest = hypot(point.x - first.x, point.y - first.y)
        for pair in zip(path, path.dropFirst()) {
            let dx = pair.1.x - pair.0.x, dy = pair.1.y - pair.0.y
            let lengthSquared = dx * dx + dy * dy
            let t = lengthSquared > 0 ? min(1, max(0, ((point.x - pair.0.x) * dx + (point.y - pair.0.y) * dy) / lengthSquared)) : 0
            nearest = min(nearest, hypot(point.x - pair.0.x - t * dx, point.y - pair.0.y - t * dy))
        }
        return nearest
    }
}
