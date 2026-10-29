import CoreGraphics
import Foundation

// Store the final vector silhouette; screen, selection and PDF use the same geometry.
struct InkVectorPath: Codable, Equatable {
    struct Element: Codable, Equatable {
        var kind: Int
        var points: [CGPoint]
    }
    var elements: [Element]
    init(_ path: CGPath) {
        var result: [Element] = []
        path.applyWithBlock { pointer in
            let item = pointer.pointee
            let count: Int
            switch item.type {
            case .moveToPoint, .addLineToPoint: count = 1
            case .addQuadCurveToPoint: count = 2
            case .addCurveToPoint: count = 3
            case .closeSubpath: count = 0
            @unknown default: count = 0
            }
            result.append(Element(kind: Int(item.type.rawValue), points: (0..<count).map { item.points[$0] }))
        }
        elements = result
    }
    var valid: Bool {
        let counts = [1, 1, 2, 3, 0]
        return elements.count <= 1_000_000 && elements.allSatisfy {
            counts.indices.contains($0.kind) && $0.points.count == counts[$0.kind] &&
            $0.points.allSatisfy { $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 1_000_000 && abs($0.y) <= 1_000_000 }
        }
    }
    var cgPath: CGPath {
        let path = CGMutablePath()
        guard valid else { return path }
        for item in elements {
            switch item.kind {
            case 0: path.move(to: item.points[0])
            case 1: path.addLine(to: item.points[0])
            case 2: path.addQuadCurve(to: item.points[1], control: item.points[0])
            case 3: path.addCurve(to: item.points[2], control1: item.points[0], control2: item.points[1])
            case 4: path.closeSubpath()
            default: break
            }
        }
        return path
    }
}
