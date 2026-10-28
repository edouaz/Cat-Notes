import UIKit

@MainActor
extension EditorSession {
    func replaceDrawing(_ replacement: InkDrawing, actionName: String) {
        let previous = canvas.drawing
        registerDrawingUndo(previous, actionName: actionName)
        canvas.drawing = replacement
        changed(replacement)
        refreshUndoAvailability()
    }

    func registerDrawingUndo(_ previous: InkDrawing, actionName: String) {
        canvas.undoManager?.registerUndo(withTarget: self) { session in session.replaceDrawing(previous, actionName: actionName) }
        canvas.undoManager?.setActionName(actionName)
    }

    @discardableResult
    func moveSelection(inside path: UIBezierPath, by requested: CGPoint) async -> Bool {
        guard requested.x.isFinite, requested.y.isFinite, let pageID = page?.id,
              await flush(), let original = page, original.id == pageID else { return false }
        let snapshot = SelectionMoveSnapshot(page: original, drawing: canvas.drawing, path: path, settings: toolSettings)
        guard !snapshot.isEmpty else { return false }
        let delta = snapshot.clamped(requested)
        guard delta != .zero else { return false }
        let moved = (original.elements ?? []).map { element in
            var element = element
            if snapshot.elementIDs.contains(element.id) { element.x += delta.x; element.y += delta.y }
            return element
        }
        let strokes = canvas.drawing.strokes.enumerated().map { index, stroke in
            guard snapshot.strokeIndices.contains(index) else { return stroke }
            return InkDrawing(strokes: [stroke]).transformed(using: CGAffineTransform(translationX: delta.x, y: delta.y)).strokes[0]
        }
        replaceContent(InkDrawing(strokes: strokes), elements: moved, actionName: "Move selection")
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
        let strokes = drawing.strokes.enumerated().compactMap { index, stroke -> InkStroke? in
            guard selected[index] else { return stroke }
            return deleting ? nil : InkDrawing(strokes: [stroke]).transformed(using: transform).strokes.first
        }
        replaceContent(InkDrawing(strokes: strokes), elements: updated, actionName: deleting ? "Delete selection" : "Resize selection")
        return await flush()
    }
}

// Shared by the drag preview and the committed edit, including page-edge constraints.
struct SelectionMoveSnapshot {
    let strokeIndices: Set<Int>
    let elementIDs: Set<UUID>
    let ink: InkDrawing
    let elements: [PageElement]
    let bounds: CGRect
    let pageSize: CGSize
    var isEmpty: Bool { strokeIndices.isEmpty && elementIDs.isEmpty }

    init(page: NotePage, drawing: InkDrawing, path: UIBezierPath, settings: EditorToolSettings) {
        let indices = Set(drawing.strokes.indices.filter { settings.includeHandwriting && DocumentClipboard.contains(drawing.strokes[$0], inside: path) })
        strokeIndices = indices
        ink = InkDrawing(strokes: drawing.strokes.enumerated().filter { indices.contains($0.offset) }.map(\.element))
        elements = DocumentClipboard.selectedElements(page, inside: path, settings: settings)
        elementIDs = Set(elements.map(\.id))
        var rect = ink.strokes.isEmpty ? CGRect.null : ink.bounds
        for item in elements { rect = rect.union(CGRect(x: item.x, y: item.y, width: item.width, height: item.height)) }
        bounds = rect
        pageSize = PageRenderer.size(page)
    }

    func clamped(_ delta: CGPoint) -> CGPoint {
        guard !isEmpty, delta.x.isFinite, delta.y.isFinite else { return .zero }
        return CGPoint(x: min(max(delta.x, -bounds.minX), max(-bounds.minX, pageSize.width - bounds.maxX)),
                       y: min(max(delta.y, -bounds.minY), max(-bounds.minY, pageSize.height - bounds.maxY)))
    }
}
