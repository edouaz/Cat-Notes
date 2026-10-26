import PencilKit
import UIKit

@MainActor
extension EditorSession {
    func replaceDrawing(_ replacement: PKDrawing, actionName: String) {
        let previous = canvas.drawing
        registerDrawingUndo(previous, actionName: actionName)
        canvas.drawing = replacement
        changed(replacement)
        refreshUndoAvailability()
    }

    func registerDrawingUndo(_ previous: PKDrawing, actionName: String) {
        canvas.undoManager?.registerUndo(withTarget: self) { session in session.replaceDrawing(previous, actionName: actionName) }
        canvas.undoManager?.setActionName(actionName)
    }

    @discardableResult
    func moveSelection(inside path: UIBezierPath, by requested: CGPoint) async -> Bool {
        guard requested.x.isFinite, requested.y.isFinite, await flush(), let original = page else { return false }
        let drawing = canvas.drawing
        let ink = toolSettings.includeHandwriting ? DocumentClipboard.selectedInk(drawing, inside: path) : PKDrawing()
        let elements = DocumentClipboard.selectedElements(original, inside: path, settings: toolSettings)
        guard !ink.strokes.isEmpty || !elements.isEmpty else { return false }
        var bounds = ink.strokes.isEmpty ? CGRect.null : ink.bounds
        for element in elements { bounds = bounds.union(CGRect(x: element.x, y: element.y, width: element.width, height: element.height)) }
        let size = PageRenderer.size(original)
        let delta = CGPoint(x: min(max(requested.x, -bounds.minX), max(-bounds.minX, size.width - bounds.maxX)),
                            y: min(max(requested.y, -bounds.minY), max(-bounds.minY, size.height - bounds.maxY)))
        guard delta != .zero else { return false }
        let selectedIDs = Set(elements.map(\.id))
        let moved = (original.elements ?? []).map { element in
            var element = element
            if selectedIDs.contains(element.id) { element.x += delta.x; element.y += delta.y }
            return element
        }
        let strokes = drawing.strokes.map { stroke in
            guard toolSettings.includeHandwriting, DocumentClipboard.contains(stroke, inside: path) else { return stroke }
            return PKDrawing(strokes: [stroke]).transformed(using: CGAffineTransform(translationX: delta.x, y: delta.y)).strokes[0]
        }
        replaceContent(PKDrawing(strokes: strokes), elements: moved, actionName: "Déplacer la sélection")
        return await flush()
    }

    @discardableResult
    func transformSelection(inside path: UIBezierPath, scale: CGFloat, deleting: Bool = false) async -> Bool {
        guard scale.isFinite, (0.1...10).contains(scale), await flush(), let original = page else { return false }
        let drawing = canvas.drawing
        let elements = DocumentClipboard.selectedElements(original, inside: path, settings: toolSettings)
        let selected = drawing.strokes.map { toolSettings.includeHandwriting && DocumentClipboard.contains($0, inside: path) }
        guard selected.contains(true) || !elements.isEmpty else { return false }
        let ids = Set(elements.map(\.id))
        var bounds = CGRect.null
        for (index, stroke) in drawing.strokes.enumerated() where selected[index] { bounds = bounds.union(stroke.renderBounds) }
        for item in elements { bounds = bounds.union(CGRect(x: item.x, y: item.y, width: item.width, height: item.height)) }
        let size = PageRenderer.size(original)
        let factor = min(scale, size.width / max(1, bounds.width), size.height / max(1, bounds.height))
        let x = min(max(0, bounds.midX - bounds.width * factor / 2), size.width - bounds.width * factor)
        let y = min(max(0, bounds.midY - bounds.height * factor / 2), size.height - bounds.height * factor)
        let transform = CGAffineTransform(a: factor, b: 0, c: 0, d: factor, tx: x - bounds.minX * factor, ty: y - bounds.minY * factor)
        var updated: [PageElement] = []
        for var item in original.elements ?? [] {
            if ids.contains(item.id) {
                if deleting { continue }
                item.x = item.x * factor + transform.tx; item.y = item.y * factor + transform.ty
                item.width *= factor; item.height *= factor
                if item.kind == .text { item.textFontSize = min(96, max(8, (item.textFontSize ?? 20) * factor)) }
            }
            updated.append(item)
        }
        let strokes = drawing.strokes.enumerated().compactMap { index, stroke -> PKStroke? in
            guard selected[index] else { return stroke }
            return deleting ? nil : PKDrawing(strokes: [stroke]).transformed(using: transform).strokes.first
        }
        replaceContent(PKDrawing(strokes: strokes), elements: updated, actionName: deleting ? "Supprimer la sélection" : "Redimensionner la sélection")
        return await flush()
    }
}
