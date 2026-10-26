import PencilKit
import UIKit

enum StrokeProcessing {
    // Dossier routine 0x101de94ec; its association with the UI slider is unproven.
    static func stabilizationInterval(_ level: Double) -> Double? {
        guard level.isFinite, level >= 0.01 else { return nil }
        return min(level, 1) * Double(bitPattern: 0x3fa47ae147ae147a) + Double(bitPattern: 0x3f947ae147ae147b)
    }
    static func snappedLine(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count == 2 else { return points }
        let start = points[0], end = points[1]
        let dx = end.x - start.x, dy = end.y - start.y
        let angle = atan2(dy, dx), target = (angle / (.pi / 4)).rounded() * (.pi / 4)
        // CatNotes tolerance; the dossier does not establish Goodnotes' snapping thresholds.
        guard abs(angle - target) <= .pi / 36 else { return points }
        let length = hypot(dx, dy)
        return [start, CGPoint(x: start.x + cos(target) * length, y: start.y + sin(target) * length)]
    }
    // shortcut: custom nib and smoothing apply after lift; use a custom input renderer when live parity is required.
    static func process(_ stroke: PKStroke, tool: DrawingToolKind, width: Double, settings: EditorToolSettings, shapeHeld: Bool) -> PKStroke? {
        guard width.isFinite, width > 0 else { return nil }
        let pen = tool == .pen || tool == .fountainPen
        var shape = shapeHeld && settings.rulerEnabled != true && settings.shapeRecognitionEnabled && (pen || tool == .marker)
            ? ShapeRecognition.recognize(stroke.path.map(\.location)) : nil
        if settings.shapeAngleSnap == true, let points = shape, points.count == 2 {
            let world = points.map { $0.applying(stroke.transform) }
            shape = snappedLine(world).map { $0.applying(stroke.transform.inverted()) }
        }
        guard pen || tool == .marker || shape != nil else { return nil }
        let original = Array(stroke.path)
        guard !original.isEmpty, original.allSatisfy({ $0.location.x.isFinite && $0.location.y.isFinite && $0.timeOffset.isFinite }) else { return nil }
        let level = settings.stabilization(for: tool)
        let smoothing = level.isFinite ? min(1, max(0, level / 100)) : 0
        if !pen && shape == nil && smoothing == 0 { return nil }
        let radius = Int((smoothing * 6).rounded())
        var locations = original.map(\.location)
        if let shape {
            locations = shape.count <= 5 ? shape.flatMap { [$0, $0, $0] } : shape
        } else if (pen || tool == .marker) && radius > 0 && original.count > 2 {
            // CatNotes uses a time window after lift; this is not Goodnotes' recovered accumulation pipeline.
            let meanInterval = max(0.01, (original.last?.timeOffset ?? 0) / Double(original.count - 1))
            let window = max(stabilizationInterval(smoothing) ?? 0, meanInterval * Double(radius))
            for index in 1..<(original.count - 1) {
                let samples = original[max(0, index - radius)...min(original.count - 1, index + radius)]
                    .filter { abs($0.timeOffset - original[index].timeOffset) <= window }
                let average = samples.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.location.x, y: $0.y + $1.location.y) }
                locations[index] = CGPoint(x: original[index].location.x * (1 - smoothing) + average.x / CGFloat(samples.count) * smoothing,
                                           y: original[index].location.y * (1 - smoothing) + average.y / CGFloat(samples.count) * smoothing)
            }
        }
        let duration = max(0.01, original.last?.timeOffset ?? 0.01)
        let points = locations.enumerated().map { index, location in
            let progress = Double(index) / Double(max(1, locations.count - 1))
            let source = original[min(original.count - 1, Int((progress * Double(original.count - 1)).rounded()))]
            var size = source.size
            var azimuth = source.azimuth
            if pen {
                let rawPressure = min(1, max(0, source.force))
                let preference = settings.pressureSensitivity ?? 0.5
                let sensitivity = preference.isFinite ? min(1, max(0, preference)) : 0.5
                // CatNotes response curve; the dossier establishes levels, not their transfer function.
                let pressure = sensitivity <= 0.5
                    ? 1 + (rawPressure - 1) * sensitivity * 2
                    : pow(rawPressure, 1 + (sensitivity - 0.5) * 2)
                switch settings.penStyle {
                case .ballpoint: size = CGSize(width: width, height: width)
                case .fountain:
                    let sourceIndex = min(original.count - 1, Int((progress * Double(original.count - 1)).rounded()))
                    let before = original[max(0, sourceIndex - 1)].location, after = original[min(original.count - 1, sourceIndex + 1)].location
                    let direction = atan2(after.y - before.y, after.x - before.x)
                    let diameter = width * (0.5 + pressure) * (0.55 + abs(sin(direction - .pi / 4)))
                    size = CGSize(width: diameter, height: diameter * 0.55)
                    azimuth = .pi / 4
                case .brush:
                    let taper = min(1, max(0.25, min(progress, 1 - progress) * 8))
                    let diameter = width * (0.25 + pressure * 1.75) * taper
                    size = CGSize(width: diameter, height: diameter)
                }
            }
            return PKStrokePoint(location: location, timeOffset: shape == nil ? source.timeOffset : duration * progress, size: size, opacity: source.opacity,
                                 force: source.force, azimuth: azimuth, altitude: source.altitude)
        }
        return PKStroke(ink: stroke.ink, path: PKStrokePath(controlPoints: points, creationDate: stroke.path.creationDate),
                        transform: stroke.transform, mask: stroke.mask, randomSeed: stroke.randomSeed)
    }
}
