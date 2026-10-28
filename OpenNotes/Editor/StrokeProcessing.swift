import UIKit

enum StrokeProcessing {
    static func stabilizationInterval(_ level: Double) -> Double? {
        guard level.isFinite, level >= 0.01 else { return nil }
        return min(level, 1) * 0.04 + 0.02
    }

    static func snappedLine(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count == 2 else { return points }
        let start = points[0], end = points[1]
        let dx = end.x - start.x, dy = end.y - start.y
        let angle = atan2(dy, dx), target = (angle / (.pi / 4)).rounded() * (.pi / 4)
        guard abs(angle - target) <= .pi / 36 else { return points }
        let length = hypot(dx, dy)
        return [start, CGPoint(x: start.x + cos(target) * length, y: start.y + sin(target) * length)]
    }

    // Causal filtering keeps the prefix identical in live and saved geometry.
    static func process(_ stroke: InkStroke, tool: DrawingToolKind, width: Double, settings: EditorToolSettings, shapeHeld: Bool) -> InkStroke? {
        guard width.isFinite, width > 0, tool.isWritingTool else { return nil }
        let original = stroke.rawSamples.isEmpty ? Array(stroke.path) : stroke.rawSamples
        guard !original.isEmpty, original.allSatisfy({ $0.location.x.isFinite && $0.location.y.isFinite && $0.timeOffset.isFinite }) else { return nil }
        let pen = tool == .pen || tool == .fountainPen
        let level = settings.stabilization(for: tool)
        let smoothing = level.isFinite ? min(1, max(0, level / 100)) : 0
        let response = min(1, max(0, settings.pressureSensitivity ?? 0.5))
        let kind: EditorToolSettings.PenStyle = tool == .fountainPen ? .fountain : settings.penStyle
        let style = InkStyle(kind: kind, width: width, pattern: pen ? settings.inkPattern ?? .solid : .solid,
                             sharpness: pen && kind != .ballpoint ? min(1, max(0, settings.tipSharpness ?? 0)) : 0,
                             stabilization: smoothing, pressureResponse: response)
        var locations = original.map(\.location)
        var shape = shapeHeld && settings.rulerEnabled != true && settings.shapeRecognitionEnabled && (pen || tool == .marker)
            ? ShapeRecognition.recognize(locations) : nil
        if settings.shapeAngleSnap == true, let points = shape, points.count == 2 {
            shape = snappedLine(points.map { $0.applying(stroke.transform) }).map { $0.applying(stroke.transform.inverted()) }
        }
        if let shape {
            locations = shape
        } else if smoothing > 0, original.count > 1 {
            var velocity = CGPoint.zero
            for index in 1..<original.count {
                let dt = max(0.001, original[index].timeOffset - original[index - 1].timeOffset)
                let derivativeAlpha = CGFloat(1 / (1 + 1 / (2 * Double.pi * dt)))
                let current = original[index].location, before = original[index - 1].location
                velocity.x += derivativeAlpha * ((current.x - before.x) / dt - velocity.x)
                velocity.y += derivativeAlpha * ((current.y - before.y) / dt - velocity.y)
                // Starting calibration in page points; real Pencil latency needs hardware measurement.
                let cutoff = 6 - 5.5 * smoothing + (0.01 - 0.008 * smoothing) * hypot(velocity.x, velocity.y)
                let alpha = CGFloat(1 / (1 + 1 / (2 * Double.pi * cutoff * dt)))
                let previous = locations[index - 1]
                locations[index] = CGPoint(x: previous.x + alpha * (current.x - previous.x),
                                           y: previous.y + alpha * (current.y - previous.y))
            }
        }
        var pressure = CGFloat(0.5)
        let duration = max(0.001, original.last?.timeOffset ?? 0)
        let controls = locations.enumerated().map { index, location -> InkStrokePoint in
            let progress = Double(index) / Double(max(1, locations.count - 1))
            let sourceIndex = shape == nil ? index : min(original.count - 1, Int((progress * Double(original.count - 1)).rounded()))
            var point = original[sourceIndex]
            let rawPressure = point.force.isFinite ? min(1, max(0, point.force)) : 0.5
            pressure = index == 0 ? rawPressure : pressure + 0.65 * (rawPressure - pressure)
            let p = settings.pressureEnabled == false ? CGFloat(0.5) : pressure
            let q = p * p * (3 - 2 * p)
            let power = 1.4 - 0.7 * response
            var diameter = width
            if pen, kind == .fountain { diameter *= 0.60 + 0.75 * pow(Double(q), power) }
            if pen, kind == .brush { diameter *= 0.20 + 1.75 * pow(Double(q), power) }
            if tool == .pencil, settings.pressureEnabled != false { diameter *= 0.5 + Double(p) }
            point.location = location
            if shape != nil { point.timeOffset = duration * progress }
            point.size = CGSize(width: diameter, height: diameter)
            if settings.tiltEnabled == false { point.altitude = .pi / 2 }
            return point
        }
        var result = stroke
        result.path = InkStrokePath(controlPoints: controls, creationDate: stroke.path.creationDate)
        result.rawSamples = original
        result.style = style
        return result
    }
}
