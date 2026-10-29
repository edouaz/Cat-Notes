import CoreGraphics
import Foundation

// Built once per gesture from immutable page geometry; query only cells crossed by the eraser.
struct InkSpatialIndex {
    private var cells: [Int: Set<UUID>] = [:]
    private var largeObjects: Set<UUID> = []
    private static let cellSize: CGFloat = 128
    init(_ drawing: InkDrawing) {
        for stroke in drawing.strokes {
            let rect = stroke.renderBounds
            guard !rect.isNull, rect.minX.isFinite, rect.minY.isFinite, rect.maxX.isFinite, rect.maxY.isFinite else { continue }
            let xs = Int(floor(rect.minX / Self.cellSize))...Int(floor(rect.maxX / Self.cellSize))
            let ys = Int(floor(rect.minY / Self.cellSize))...Int(floor(rect.maxY / Self.cellSize))
            if xs.count * ys.count > 4096 { largeObjects.insert(stroke.id); continue }
            for x in xs { for y in ys { cells[Self.key(x, y), default: []].insert(stroke.id) } }
        }
    }
    func query(_ rect: CGRect) -> Set<UUID> {
        guard !rect.isNull, rect.minX.isFinite, rect.minY.isFinite, rect.maxX.isFinite, rect.maxY.isFinite else { return [] }
        let xs = Int(floor(rect.minX / Self.cellSize))...Int(floor(rect.maxX / Self.cellSize))
        let ys = Int(floor(rect.minY / Self.cellSize))...Int(floor(rect.maxY / Self.cellSize))
        if xs.count * ys.count > 4096 { return cells.values.reduce(largeObjects) { $0.union($1) } }
        var result = largeObjects
        for x in xs { for y in ys { result.formUnion(cells[Self.key(x, y)] ?? []) } }
        return result
    }
    private static func key(_ x: Int, _ y: Int) -> Int { (x &* 73_856_093) ^ (y &* 19_349_663) }
}
