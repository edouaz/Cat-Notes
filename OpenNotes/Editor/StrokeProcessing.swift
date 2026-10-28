import PencilKit
import UIKit

enum StrokeProcessing {
    // A longer filter time constant suppresses more hand tremor.
    static func stabilizationInterval(_ level: Double) -> Double? {
        guard level.isFinite, level >= 0.01 else { return nil }
        return min(level, 1) * 0.04 + 0.02
    }
    static func snappedLine(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count == 2 else { return points }
        let start = points[0], end = points[1]
        let dx = end.x - start.x, dy = end.y - start.y
        let angle = atan2(dy, dx), target = (angle / (.pi / 4)).rounded() * (.pi / 4)
        // OpenNotes tolerance; the dossier does not establish Goodnotes' snapping thresholds.
        guard abs(angle - target) <= .pi / 36 else { return points }
        let length = hypot(dx, dy)
        return [start, CGPoint(x: start.x + cos(target) * length, y: start.y + sin(target) * length)]
    }
    // The causal filter gives live previews and committed strokes the same geometry.
    static func process(_ stroke: PKStroke, tool: DrawingToolKind, width: Double, settings: EditorToolSettings, shapeHeld: Bool) -> PKStroke? {
        guard width.isFinite, width > 0 else { return nil }
        let pen = tool == .pen || tool == .fountainPen
        var shape = shapeHeld && settings.rulerEnabled != true && settings.shapeRecognitionEnabled && (pen || tool == .marker)
            ? ShapeRecognition.recognize(stroke.path.map(\.location)) : nil
        if settings.shapeAngleSnap == true, let points = shape, points.count == 2 {
            let world = points.map { $0.applying(stroke.transform) }
            shape = snappedLine(world).map { $0.applying(stroke.transform.inverted()) }
        }
        guard tool.isWritingTool else { return nil }
        let original = Array(stroke.path)
        guard !original.isEmpty, original.allSatisfy({ $0.location.x.isFinite && $0.location.y.isFinite && $0.timeOffset.isFinite }) else { return nil }
        let level = settings.stabilization(for: tool)
        let smoothing = level.isFinite ? min(1, max(0, level / 100)) : 0
        if !pen && shape == nil && smoothing == 0 && settings.pressureEnabled == nil && settings.tiltEnabled == nil { return nil }
        var locations = original.map(\.location)
        if let shape {
            locations = shape.count <= 5 ? shape.flatMap { [$0, $0, $0] } : shape
        } else if smoothing > 0 && original.count > 1 {
            let timeConstant = (stabilizationInterval(smoothing) ?? 0) * smoothing
            for index in 1..<original.count {
                let elapsed = max(1.0 / 240, original[index].timeOffset - original[index - 1].timeOffset)
                let weight = CGFloat(elapsed / (timeConstant + elapsed))
                let previous = locations[index - 1], current = original[index].location
                locations[index] = CGPoint(x: previous.x + weight * (current.x - previous.x),
                                           y: previous.y + weight * (current.y - previous.y))
            }
        }
        let duration = max(0.01, original.last?.timeOffset ?? 0.01)
        let points = locations.enumerated().map { index, location in
            let progress = Double(index) / Double(max(1, locations.count - 1))
            let source = original[min(original.count - 1, Int((progress * Double(original.count - 1)).rounded()))]
            var size = source.size
            var azimuth = source.azimuth
            let force = settings.pressureEnabled == false ? CGFloat(1) : source.force
            let altitude = settings.tiltEnabled == false ? CGFloat.pi / 2 : source.altitude
            if pen {
                let rawPressure = min(1, max(0, force))
                let preference = settings.pressureSensitivity ?? 0.5
                let sensitivity = preference.isFinite ? min(1, max(0, preference)) : 0.5
                // OpenNotes response curve; the dossier establishes levels, not their transfer function.
                let pressure = sensitivity <= 0.5
                    ? 1 + (rawPressure - 1) * sensitivity * 2
                    : pow(rawPressure, 1 + (sensitivity - 0.5) * 2)
                switch settings.penStyle {
                case .ballpoint:
                    let diameter = width * (settings.pressureEnabled == true ? 0.5 + pressure : 1)
                    size = CGSize(width: diameter, height: diameter)
                case .fountain:
                    let sourceIndex = min(original.count - 1, Int((progress * Double(original.count - 1)).rounded()))
                    let before = original[max(0, sourceIndex - 1)].location, after = original[sourceIndex].location
                    let direction = atan2(after.y - before.y, after.x - before.x)
                    let diameter = width * (0.5 + pressure) * (0.55 + abs(sin(direction - .pi / 4)))
                    size = CGSize(width: diameter, height: diameter * 0.55)
                    azimuth = .pi / 4
                case .brush:
                    let taper = min(1, max(0.25, Double(index) / 4))
                    let diameter = width * (0.25 + pressure * 1.75) * taper
                    size = CGSize(width: diameter, height: diameter)
                }
            }
            if tool == .pencil, let pressureEnabled = settings.pressureEnabled {
                let diameter = width * (pressureEnabled ? 0.5 + min(1, max(0, force)) : 1)
                size = CGSize(width: diameter, height: diameter)
            }
            if tool != .marker && settings.tiltEnabled == true, altitude.isFinite {
                let spread = 1 + max(0, 1 - sin(altitude))
                size = CGSize(width: size.width * spread, height: size.height)
            } else if settings.tiltEnabled == false && !pen {
                azimuth = 0
            }
            return PKStrokePoint(location: location, timeOffset: shape == nil ? source.timeOffset : duration * progress, size: size, opacity: source.opacity,
                                 force: force, azimuth: azimuth, altitude: altitude)
        }
        return PKStroke(ink: stroke.ink, path: PKStrokePath(controlPoints: points, creationDate: stroke.path.creationDate),
                        transform: stroke.transform, mask: stroke.mask, randomSeed: stroke.randomSeed)
    }
}
