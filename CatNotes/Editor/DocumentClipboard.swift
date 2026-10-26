import UIKit
import PencilKit

// Images stay standard PNG; editable ink uses its own pasteboard type.
enum DocumentClipboard {
    static let inkType = "fr.catnotes.drawing"
    static let maximumBytes = 20_000_000
    static func filteredPage(_ page: NotePage, settings: EditorToolSettings) -> NotePage {
        var filtered = page
        filtered.elements?.removeAll { item in
            (item.kind == .text && settings.includeText == false) || (item.kind == .image && !settings.includeImages) || (item.kind == .stickyNote && !settings.includeStickyNotes)
        }
        return filtered
    }
    static func selectedElements(_ page: NotePage, inside path: UIBezierPath, settings: EditorToolSettings) -> [PageElement] {
        return (filteredPage(page, settings: settings).elements ?? []).filter { item in
            guard item.kind != .highlight else { return false }
            let folded = item.kind == .stickyNote && item.collapsed == true
            let rect = CGRect(x: item.x, y: item.y, width: folded ? 44 : item.width, height: folded ? 44 : item.height)
            return rect.intersects(path.bounds) && path.cgPath.intersects(CGPath(rect: rect, transform: nil), using: path.usesEvenOddFillRule ? .evenOdd : .winding)
        }
    }
    static func selectedInk(_ drawing: PKDrawing, inside path: UIBezierPath) -> PKDrawing {
        PKDrawing(strokes: drawing.strokes.filter { contains($0, inside: path) })
    }
    static func contains(_ stroke: PKStroke, inside path: UIBezierPath) -> Bool {
        stroke.renderBounds.intersects(path.bounds) && stroke.path.interpolatedPoints(by: .distance(4)).contains {
            (stroke.mask?.contains($0.location) ?? true) && path.contains($0.location.applying(stroke.transform))
        }
    }
    static func copyInk(_ drawing: PKDrawing) throws {
        guard !drawing.strokes.isEmpty else { throw CocoaError(.validationMissingMandatoryProperty) }
        let data = drawing.dataRepresentation()
        guard data.count <= maximumBytes else { throw CocoaError(.fileWriteOutOfSpace) }
        UIPasteboard.general.setItems([[inkType: data]], options: [.localOnly: true])
    }
    static func decodeInk(_ data: Data, at point: CGPoint, pageSize: CGSize) throws -> PKDrawing {
        guard data.count <= maximumBytes else { throw CocoaError(.fileReadTooLarge) }
        let drawing = try PKDrawing(data: data)
        let bounds = drawing.bounds
        guard !drawing.strokes.isEmpty, drawing.strokes.count <= 10_000,
              bounds.width.isFinite, bounds.height.isFinite, bounds.minX.isFinite, bounds.minY.isFinite,
              bounds.width > 0, bounds.height > 0, pageSize.width > 0, pageSize.height > 0 else { throw CocoaError(.fileReadCorruptFile) }
        let scale = min(1, pageSize.width / bounds.width, pageSize.height / bounds.height)
        let x = min(max(0, point.x), max(0, pageSize.width - bounds.width * scale))
        let y = min(max(0, point.y), max(0, pageSize.height - bounds.height * scale))
        return drawing.transformed(using: CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: x - bounds.minX * scale, ty: y - bounds.minY * scale))
    }
}
