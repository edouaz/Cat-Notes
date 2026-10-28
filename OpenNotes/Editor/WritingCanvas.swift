import SwiftUI
import PencilKit

struct WritingCanvas: UIViewRepresentable {
    @ObservedObject var session: EditorSession
    var finger: Bool
    var reading: Bool
    var zoomWindow = false
    var verticalPaging = false
    var editingImages = false
    var pageDirection = 1
    var previousPreview: UIImage?
    var nextPreview: UIImage?
    var hasPrevious = false
    var hasNext = false
    var selectionMode = false
    var immediateSelection = false
    var selectedRect: ((CGRect, UIBezierPath, PageSelectionAction) -> Void)?
    var pasted: (() -> Void)?
    var editNote: ((PageElement) -> Void)?
    var imageEditingEnded: (() -> Void)?
    var selectionMoved: ((UIBezierPath, CGPoint) async -> Bool)?
    var onEraserStroke: (([CGPoint]) -> Void)?
    var prepare: ((Int) -> Void)?
    var addPage: ((Int) async -> Bool)?
    var navigate: ((Int) async -> Bool)?
    func makeCoordinator() -> Coordinator { Coordinator(session: session, zoomWindow: zoomWindow) }
    func makeUIView(context: Context) -> PageScrollView {
        let view = PageScrollView(canvas: context.coordinator.activeCanvas)
        context.coordinator.container = view
        view.canvas.delegate = context.coordinator
        view.onWindowReady = { [weak coordinator = context.coordinator] in
            coordinator?.updateInteraction()
        }
        view.onNavigate = navigate
        return view
    }
    func updateUIView(_ view: PageScrollView, context: Context) {
        guard let page = session.page else { return }
        let canvas = view.canvas
        if view.pageSize != PageRenderer.size(page) { view.pageSize = PageRenderer.size(page); view.needsFit = true; view.setNeedsLayout() }
        context.coordinator.reading = reading
        context.coordinator.updateInteraction()
        view.onNavigate = navigate
        view.pageTurn.previous = previousPreview; view.pageTurn.next = nextPreview
        view.pageTurn.canPrevious = hasPrevious; view.pageTurn.canNext = hasNext
        view.pageTurn.addPage = addPage
        view.pageTurn.prepare = prepare
        let selecting = selectionMode || (!reading && !editingImages && session.selectedTool == .lasso)
        view.pageTurn.disabled = selecting || editingImages || session.busy || (!reading && session.selectedTool == .lasso)
        view.onImageEditingEnded = imageEditingEnded
        view.touchObserver.pageID = page.id
        view.touchObserver.erasing = !reading && !editingImages && !selecting && session.selectedTool == .eraser && (onEraserStroke != nil || session.toolSettings.eraserMode == .intelligent)
        view.eraserCursorEnabled = !reading && !editingImages && !selecting && session.selectedTool == .eraser && session.toolSettings.eraserMode != .pixel
        if #available(iOS 16.4, *), let eraser = session.tool as? PKEraserTool {
            view.eraserCursorWidth = eraser.width
        } else { view.eraserCursorWidth = session.toolSettings.eraserWidth }
        view.touchObserver.observeEraser = view.eraserCursorEnabled
        view.touchObserver.eraserPointer = { [weak view] point in view?.showEraserCursor(at: point) }
        view.touchObserver.observeWriting = !reading && !editingImages && !selecting && session.selectedTool.isWritingTool
        view.touchObserver.observeShapes = session.toolSettings.rulerEnabled != true && !reading && !editingImages && !selecting && session.toolSettings.shapeRecognitionEnabled && [.pen, .fountainPen, .marker].contains(session.selectedTool)
        view.touchObserver.fingerDrawing = finger
        view.touchObserver.erased = { [weak view, weak session = session] points in
            guard let view, let session else { return }
            let logical = points.map { CGPoint(x: ($0.x + view.canvas.contentOffset.x) / view.canvas.zoomScale, y: ($0.y + view.canvas.contentOffset.y) / view.canvas.zoomScale) }
            if let onEraserStroke { onEraserStroke(logical) }
            else {
                let result = EraserEditing.erase(session.canvas.drawing, along: logical, width: session.toolSettings.eraserWidth, mode: session.toolSettings.eraserMode)
                if result.dataRepresentation() != session.canvas.drawing.dataRepresentation() { session.replaceDrawing(result, actionName: "Clear") }
            }
        }
        view.touchObserver.held = { [weak coordinator = context.coordinator] points in coordinator?.previewHeldShape(points) }
        view.touchObserver.holdCancelled = { [weak coordinator = context.coordinator] in
            coordinator?.clearHeldShape()
        }
        view.touchObserver.cancelledStroke = { [weak coordinator = context.coordinator] in
            coordinator?.cancelStroke(restoringDrawing: true)
        }
        view.touchObserver.beganStroke = { [weak coordinator = context.coordinator] in
            guard let coordinator, coordinator.session.selectedTool.isWritingTool else { return }
            coordinator.clearHeldShape()
            coordinator.canvasViewDidBeginUsingTool(coordinator.activeCanvas)
        }
        view.touchObserver.sampled = { [weak coordinator = context.coordinator] samples in coordinator?.previewSamples(samples) }
        view.touchObserver.adjustedShape = { [weak coordinator = context.coordinator] point in coordinator?.adjustHeldShape(point) }
        view.configureSelection(selecting, session: session, immediate: immediateSelection, shape: session.toolSettings.lassoShape, moved: selectionMoved, selected: selectedRect)
        view.onPaste = { point in Task { await session.paste(at: point); pasted?() } }
        view.verticalPaging = verticalPaging
        view.fingerDrawing = finger
        context.coordinator.configureTool(canvas)
        canvas.isRulerActive = session.toolSettings.rulerEnabled == true && !reading && !editingImages && !selecting
        canvas.drawingPolicy = finger ? .anyInput : .pencilOnly
        canvas.drawingGestureRecognizer.isEnabled = !reading && !editingImages && !selecting && !view.touchObserver.erasing
        if view.touchObserver.erasing && finger { view.pageTurn.disabled = true }
        if context.coordinator.pageID != page.id {
            context.coordinator.cancelStroke()
            context.coordinator.loading = true
            view.pageSize = PageRenderer.size(page)
            if zoomWindow || session.canvasPageID != page.id {
                canvas.drawing = session.drawing
                canvas.undoManager?.removeAllActions()
                context.coordinator.updateUndoAvailability()
                if !zoomWindow { session.canvasPageID = page.id }
            }
            context.coordinator.pageID = page.id
            view.initialZoom = zoomWindow ? 2 : nil
            view.restorePosition(page.id, noteID: session.noteID)
            view.needsFit = true
            view.setNeedsLayout()
            context.coordinator.loading = false
        }
        var paperPage = page
        paperPage.elements?.removeAll { $0.kind == .stickyNote || (!selecting && $0.kind == .image) }
        view.configureNotes(page, edit: editNote) { item, id in
            Task { await session.apply(.init(pageID: page.id, kind: item == nil ? .removeElement : .upsertElement, element: item, elementID: id)) }
        }
        view.showSearchHighlights(session.searchHighlights)
        view.paper.configure(page: paperPage, artwork: session.artwork)
        view.configureImages(!selecting ? page : nil, images: session.artwork?.images ?? [:], pencil: editingImages) { item, id in
            Task { await session.apply(.init(pageID: page.id, kind: item == nil ? .removeElement : .upsertElement, element: item, elementID: id)) }
        }
        // Keep PencilKit visible on PDF pages too; swapping an idle bitmap causes a visible handoff.
        view.layoutIfNeeded()
        view.pageTurn.pageInstalled(page.id)
    }
    static func dismantleUIView(_ view: PageScrollView, coordinator: Coordinator) {
        view.onWindowReady = nil
        coordinator.cancelStroke()
        coordinator.container = nil
        view.pageTurn.detach()
        view.detachInteractions()
        view.savePosition()
        if view.canvas.delegate === coordinator { view.canvas.delegate = nil }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let session: EditorSession
        let zoomWindow: Bool
        let zoomCanvas = PKCanvasView()
        weak var container: PageScrollView?
        var activeCanvas: PKCanvasView { zoomWindow ? zoomCanvas : session.canvas }
        var pageID: UUID?
        var loading = false
        var reading = false
        var shapeHeld = false
        private var shapeAdjustment: ShapeRecognition.Adjustment?
        private var heldStroke: PKStroke?
        private var lastAdjustmentPoint: CGPoint?
        private var previewStroke: PKStroke?
        private var lastSample: PKStrokePoint?
        private var awaitingShapeRender = false
        private var strokeCreatedAt = Date()
        private var strokeStartCount: Int?
        private var strokePageID: UUID?
        private var strokeEnded = false
        private var processingStroke = false
        private var strokeSettings = EditorToolSettings()
        private var strokeTool = DrawingToolKind.pen
        private var strokeBefore: PKDrawing?
        private var strokeUndoManagers: [UndoManager] = []
        private var interactionScheduled = false
        private var lastTool: DrawingToolKind?
        private var lastSettings: EditorToolSettings?
        private var lastWidth: Double?
        private var lastColor: UIColor?
        private var lastEraserMode: EditorToolSettings.EraserMode?
        private var lastEraserWidth: Double?
        func updateInteraction() {
            guard !interactionScheduled else { return }
            interactionScheduled = true
            // Changing UIKit focus inside updateUIView reenters SwiftUI's focus graph.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.interactionScheduled = false
                let canvas = self.activeCanvas
                guard self.container != nil, canvas.delegate === self, canvas.window?.isKeyWindow == true else { return }
                if !self.reading && !canvas.isFirstResponder { canvas.becomeFirstResponder() }
                if !self.zoomWindow { self.session.refreshUndoAvailability() }
            }
        }
        func updateUndoAvailability() {
            guard !zoomWindow else { return }
            // Undo groups close inside PencilKit callbacks and SwiftUI updates.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.container != nil, self.session.canvas.delegate === self else { return }
                self.session.refreshUndoAvailability()
            }
        }
        @objc private func undoHistoryChanged(_ notification: Notification) {
            guard let manager = notification.object as? UndoManager, manager === activeCanvas.undoManager else { return }
            updateUndoAvailability()
        }
        func configureTool(_ canvas: PKCanvasView) {
            let color = UIColor(session.inkColor)
            let eraserChanged = session.selectedTool == .eraser &&
                (lastEraserMode != session.toolSettings.eraserMode || lastEraserWidth != session.toolSettings.eraserWidth)
            guard lastTool != session.selectedTool || lastSettings != session.toolSettings || eraserChanged || (session.selectedTool.isWritingTool && (lastWidth != session.inkWidth || lastColor != color)) else { return }
            canvas.tool = session.tool
            lastSettings = session.toolSettings
            lastTool = session.selectedTool; lastWidth = session.inkWidth; lastColor = color
            lastEraserMode = session.toolSettings.eraserMode; lastEraserWidth = session.toolSettings.eraserWidth
        }
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { container?.savePosition() }
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) { if !decelerate { container?.savePosition() } }
        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            container?.alignBackground(); container?.savePosition()
        }
        init(session: EditorSession, zoomWindow: Bool) {
            self.session = session; self.zoomWindow = zoomWindow
            super.init()
            for name in [Notification.Name.NSUndoManagerDidCloseUndoGroup, Notification.Name.NSUndoManagerDidUndoChange, Notification.Name.NSUndoManagerDidRedoChange] {
                NotificationCenter.default.addObserver(self, selector: #selector(undoHistoryChanged(_:)), name: name, object: nil)
            }
        }
        deinit {
            strokeUndoManagers.forEach { $0.enableUndoRegistration() }
            NotificationCenter.default.removeObserver(self)
        }
        func scrollViewDidScroll(_ scrollView: UIScrollView) { container?.alignBackground() }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { container?.alignBackground() }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !loading else { return }
            if let previewStroke, let previous = strokeBefore, !processingStroke {
                session.changed(PKDrawing(strokes: previous.strokes + [previewStroke]))
            } else {
                if zoomWindow { session.canvas.drawing = canvasView.drawing }
                session.changed(canvasView.drawing)
            }
            if strokeEnded && !processingStroke { finishStroke(canvasView) }
            updateUndoAvailability()
        }
        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            guard strokeStartCount == nil else { return }
            clearHeldShape(); previewStroke = nil; lastSample = nil; strokeCreatedAt = Date()
            restoreStrokeUndoRegistration()
            container?.setDrawingActive(true)
            strokePageID = pageID
            strokeStartCount = canvasView.drawing.strokes.count; strokeEnded = false
            strokeSettings = session.toolSettings; strokeTool = session.selectedTool
            if strokeTool.isWritingTool {
                strokeBefore = canvasView.drawing
            }
        }
        private func restoreStrokeUndoRegistration() {
            strokeUndoManagers.forEach { $0.enableUndoRegistration() }
            strokeUndoManagers.removeAll(); strokeBefore = nil
        }
        func cancelStroke(restoringDrawing: Bool = false) {
            if restoringDrawing, strokePageID == pageID, let previous = strokeBefore {
                loading = true
                activeCanvas.drawing = previous
                if zoomWindow { session.canvas.drawing = previous }
                session.changed(previous)
                loading = false
            }
            restoreStrokeUndoRegistration()
            strokeStartCount = nil; strokePageID = nil; strokeEnded = false
            clearHeldShape(); previewStroke = nil
            container?.clearShapePreview(); container?.setDrawingActive(false)
        }
        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            strokeEnded = true
            DispatchQueue.main.async { [weak self, weak canvasView] in
                guard let self, let canvasView else { return }
                guard self.strokePageID == self.pageID else { return }
                if self.strokeTool.isWritingTool {
                    self.finishStroke(canvasView)
                    if canvasView.drawing.strokes.count == self.strokeStartCount {
                        // PencilKit may deliver the finished stroke after pen-up.
                        // Do not reset its drawing while that rendering is pending.
                        self.cancelStroke(restoringDrawing: self.shapeHeld)
                    }
                } else {
                    // Native erasing can remove strokes instead of appending one.
                    self.cancelStroke()
                }
                self.container?.setDrawingActive(false)
                self.updateUndoAvailability()
            }
        }
        func canvasViewDidFinishRendering(_ canvasView: PKCanvasView) {
            container?.selectionDidRender()
            guard awaitingShapeRender else { return }
            // A held shape is an intentional replacement. Keep its preview until
            // PencilKit has rendered it, rather than exposing an empty frame.
            awaitingShapeRender = false
            container?.clearShapePreview()
        }
        func clearHeldShape() {
            awaitingShapeRender = false
            shapeHeld = false; shapeAdjustment = nil; heldStroke = nil; lastAdjustmentPoint = nil
            container?.clearShapePreview()
        }
        private func pagePoint(_ screenPoint: CGPoint) -> CGPoint {
            CGPoint(x: (screenPoint.x + activeCanvas.contentOffset.x) / activeCanvas.zoomScale,
                    y: (screenPoint.y + activeCanvas.contentOffset.y) / activeCanvas.zoomScale)
        }
        func previewSamples(_ samples: [PKStrokePoint]) {
            // Samples are only needed to style an explicitly held shape. Freehand
            // ink is rendered and committed exclusively by PencilKit.
            guard !shapeHeld, strokePageID == pageID else { return }
            lastSample = samples.last
        }
        private func showPreview() {
            guard let container, let page = session.page, page.id == pageID,
                  let previewStroke, let previous = strokeBefore else { return }
            container.showLiveStroke(page: page, artwork: session.artwork, previous: previous, stroke: previewStroke)
            // Backgrounding or changing pages must save the same ink the user currently sees.
            session.changed(PKDrawing(strokes: previous.strokes + [previewStroke]))
        }
        func previewHeldShape(_ screenPoints: [CGPoint]) {
            guard strokeSettings.rulerEnabled != true, strokePageID == pageID,
                  let pointer = screenPoints.last, let ink = activeCanvas.tool as? PKInkingTool,
                  let recognized = ShapeRecognition.recognize(screenPoints.map(pagePoint)) else { return }
            if !shapeHeld {
                // Only an intentional shape replacement needs a custom undo step.
                // Ordinary strokes keep PencilKit's own undo registration.
                for manager in [activeCanvas.undoManager, session.canvas.undoManager].compactMap({ $0 }) where !strokeUndoManagers.contains(where: { $0 === manager }) {
                    manager.disableUndoRegistration(); strokeUndoManagers.append(manager)
                }
            }
            let points = strokeSettings.shapeAngleSnap == true ? StrokeProcessing.snappedLine(recognized) : recognized
            shapeAdjustment = ShapeRecognition.Adjustment(points: points, pointer: pagePoint(pointer))
            let source = lastSample
            let controls = (points.count <= 5 ? points.flatMap { [$0, $0, $0] } : points).enumerated().map { index, point in
                PKStrokePoint(location: point, timeOffset: Double(index) * 0.01,
                              size: source?.size ?? CGSize(width: ink.width, height: ink.width), opacity: source?.opacity ?? 1,
                              force: source?.force ?? 0.5, azimuth: source?.azimuth ?? 0, altitude: source?.altitude ?? .pi / 2)
            }
            heldStroke = PKStroke(ink: PKInk(ink.inkType, color: ink.color),
                                  path: PKStrokePath(controlPoints: controls, creationDate: strokeCreatedAt),
                                  transform: .identity, mask: nil, randomSeed: 1)
            shapeHeld = true; previewStroke = heldStroke; lastAdjustmentPoint = pointer
            showPreview()
        }
        func adjustHeldShape(_ screenPoint: CGPoint) {
            guard shapeHeld, let shapeAdjustment, let heldStroke, let previous = lastAdjustmentPoint,
                  hypot(screenPoint.x - previous.x, screenPoint.y - previous.y) >= 2 else { return }
            lastAdjustmentPoint = screenPoint
            var points = shapeAdjustment.points(at: pagePoint(screenPoint))
            if strokeSettings.shapeAngleSnap == true { points = StrokeProcessing.snappedLine(points) }
            if points.count <= 5 { points = points.flatMap { [$0, $0, $0] } }
            let controls = points.enumerated().map { index, location in
                let source = heldStroke.path[min(index, heldStroke.path.count - 1)]
                return PKStrokePoint(location: location, timeOffset: source.timeOffset, size: source.size, opacity: source.opacity,
                                     force: source.force, azimuth: source.azimuth, altitude: source.altitude)
            }
            previewStroke = PKStroke(ink: heldStroke.ink, path: PKStrokePath(controlPoints: controls, creationDate: strokeCreatedAt),
                                     transform: .identity, mask: nil, randomSeed: heldStroke.randomSeed)
            showPreview()
        }
        private func finishStroke(_ canvasView: PKCanvasView) {
            guard !loading, !processingStroke, let pageID, strokePageID == pageID, session.page?.id == pageID, let count = strokeStartCount,
                  canvasView.drawing.strokes.count == count + 1 else { return }
            strokeStartCount = nil; strokeEnded = false
            processingStroke = true
            let previous = strokeBefore
            let replacedShape = shapeHeld && previewStroke != nil
            if let replacement = previewStroke, shapeHeld {
                let drawing = PKDrawing(strokes: Array(canvasView.drawing.strokes.dropLast()) + [replacement])
                awaitingShapeRender = true
                canvasView.drawing = drawing
                if zoomWindow { session.canvas.drawing = drawing }
                session.changed(drawing)
                shapeHeld = false; shapeAdjustment = nil; heldStroke = nil; lastAdjustmentPoint = nil
                previewStroke = nil
            } else {
                // Never reassign the drawing at pen-up: even identical geometry
                // invalidates PencilKit's renderer and interrupts its live stroke.
                if zoomWindow { session.canvas.drawing = canvasView.drawing }
                session.changed(canvasView.drawing)
            }
            restoreStrokeUndoRegistration()
            if replacedShape, let previous {
                session.registerDrawingUndo(previous, actionName: "Draw")
                updateUndoAvailability()
            }
            processingStroke = false
        }
    }
}

// PencilKit owns the zoom so strokes are rerendered rather than magnifying a transformed canvas.
final class PageScrollView: UIView {
    let canvas: PKCanvasView
    private let eraserCursor = CAShapeLayer()
    var eraserCursorEnabled = false { didSet { if !eraserCursorEnabled { showEraserCursor(at: nil) } } }
    var eraserCursorWidth: CGFloat = 24
    func showEraserCursor(at point: CGPoint?) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard eraserCursorEnabled, let point else { eraserCursor.path = nil; return }
        if eraserCursor.superlayer == nil {
            eraserCursor.fillColor = UIColor.white.withAlphaComponent(0.12).cgColor
            eraserCursor.strokeColor = UIColor.darkGray.cgColor
            eraserCursor.lineWidth = 1.5
            eraserCursor.shadowColor = UIColor.white.cgColor
            eraserCursor.shadowOpacity = 1; eraserCursor.shadowRadius = 1; eraserCursor.shadowOffset = .zero
            layer.addSublayer(eraserCursor)
        }
        let diameter = max(6, eraserCursorWidth * canvas.zoomScale)
        eraserCursor.path = CGPath(ellipseIn: CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2,
                                                    width: diameter, height: diameter), transform: nil)
    }
    @objc private func eraserHovered(_ gesture: UIHoverGestureRecognizer) {
        showEraserCursor(at: gesture.state == .began || gesture.state == .changed ? gesture.location(in: self) : nil)
    }
    let paper = TiledPaperView()
    let compositedInk = TiledPaperView()
    let liveInk = LiveInkPreview()
    private var drawingActive = false
    private var usesCompositedInk = false
    private var compositeContent: (NotePage, PageArtwork?, PKDrawing)?
    private var previewPageID: UUID?
    var shapePreviewActive: Bool { previewPageID != nil }
    func configureCompositedInk(page: NotePage, artwork: PageArtwork?, drawing: PKDrawing) {
        compositeContent = (page, artwork, drawing)
        if previewPageID != nil && previewPageID != page.id { clearShapePreview() }
        usesCompositedInk = page.pdfIndex != nil && (drawing.strokes.contains { $0.ink.inkType == .marker } || page.elements?.contains { $0.kind == .highlight } == true)
        if usesCompositedInk && !shapePreviewActive {
            var page = page; page.elements?.removeAll { $0.kind == .stickyNote }
            compositedInk.configure(page: page, artwork: artwork, drawing: drawing)
        }
        updateCompositeVisibility()
    }
    func showShapePreview(page: NotePage, artwork: PageArtwork?, drawing: PKDrawing) {
        showLiveStroke(page: page, artwork: artwork, previous: PKDrawing(strokes: Array(drawing.strokes.dropLast())), stroke: drawing.strokes.last)
    }
    func showLiveStroke(page: NotePage, artwork: PageArtwork?, previous: PKDrawing, stroke: PKStroke?) {
        if previewPageID == nil {
            liveInk.frame = bounds
            liveInk.begin(page: page, artwork: artwork, previous: previous, canvas: canvas)
        }
        previewPageID = page.id
        liveInk.stroke = stroke
        liveInk.isHidden = false
        updateCompositeVisibility()
    }
    func clearShapePreview() {
        guard shapePreviewActive else { return }
        previewPageID = nil
        liveInk.isHidden = true; liveInk.clear()
        if let (page, artwork, drawing) = compositeContent { configureCompositedInk(page: page, artwork: artwork, drawing: drawing) }
        else { updateCompositeVisibility() }
    }
    func setDrawingActive(_ active: Bool) { drawingActive = active; updateCompositeVisibility() }
    private func updateCompositeVisibility() {
        compositedInk.isHidden = shapePreviewActive || !usesCompositedInk || drawingActive || imageViews.contains { $0.showsHandles }
    }
    private var imageViews: [ImageHandlesView] = []
    private var imagePage: NotePage?
    private var editingImages = false
    var onImageEditingEnded: (() -> Void)?
    private func selectImage(_ id: UUID?) { imageViews.forEach { $0.showsHandles = $0.item.id == id }; updateCompositeVisibility() }
    func deselectImages() { selectImage(nil); onImageEditingEnded?() }
    @objc private func tappedBackground(_ tap: UITapGestureRecognizer) { deselectImages() }
    func configureImages(_ page: NotePage?, images: [String: UIImage], pencil: Bool, changed: @escaping (PageElement?, UUID) -> Void) {
        let entering = pencil && !editingImages
        let leaving = !pencil && editingImages
        editingImages = pencil
        imageViews.forEach { $0.editableWithPencil = pencil }
        let sameImages = imagePage?.id == page?.id && imagePage.map(PageRenderer.size) == page.map(PageRenderer.size) &&
            imagePage?.elements?.filter { $0.kind == .image } == page?.elements?.filter { $0.kind == .image }
        let assetsChanged = imageViews.contains { view in view.item.resource.flatMap { images[$0] } !== view.preview.image }
        if sameImages && !assetsChanged {
            if entering { selectImage(imageViews.last?.item.id) }
            if leaving { selectImage(nil) }
            return
        }
        let previousIDs = Set(imageViews.map { $0.item.id })
        let selected = imagePage?.id == page?.id ? imageViews.first(where: { $0.showsHandles })?.item.id : nil
        imagePage = page
        imageViews.forEach { $0.removeFromSuperview() }; imageViews.removeAll()
        for item in page?.elements ?? [] where item.kind == .image {
            let view = ImageHandlesView(item: item, image: item.resource.flatMap { images[$0] })
            view.pageSize = pageSize; view.editableWithPencil = pencil; view.showsHandles = !leaving && selected == item.id
            view.changed = { changed($0, item.id) }
            view.selected = { [weak self] in self?.selectImage(item.id) }
            imageViews.append(view); insertSubview(view, belowSubview: canvas)
        }
        if pencil, let added = imageViews.last(where: { !previousIDs.contains($0.item.id) }) { selectImage(added.item.id) }
        else if entering { selectImage(imageViews.last?.item.id) }
        alignBackground()
    }
    lazy var pageTurn = InteractivePageTurn(view: self)
    private var noteViews: [StickyNoteControl] = []
    private var notesPage: NotePage?
    private var selectionView: PageSelectionView?
    private(set) var selectionPreview: SelectionDragPreview?
    private var selectionCommitFinished = false
    private var selectionRendered = false
    private var selectionCommitting = false
    private var selectionPageID: UUID?

    func clearSelectionPreview() {
        selectionPreview?.removeFromSuperview(); selectionPreview = nil
        selectionCommitFinished = false; selectionRendered = false; selectionCommitting = false
        selectionView?.isUserInteractionEnabled = true
    }
    func selectionDidRender() {
        guard selectionCommitting else { return }
        selectionRendered = true
        if selectionCommitFinished { clearSelectionPreview() }
    }

    private let searchLayer = CAShapeLayer()
    private var searchRects: [CGRect] = []
    func showSearchHighlights(_ rects: [CGRect]) { guard searchRects != rects else { return }; searchRects = rects; alignBackground() }
    func configureSelection(_ enabled: Bool, session: EditorSession? = nil, immediate: Bool, shape: EditorToolSettings.LassoShape = .freeform, moved: ((UIBezierPath, CGPoint) async -> Bool)? = nil, selected: ((CGRect, UIBezierPath, PageSelectionAction) -> Void)?) {
        if !enabled || selectionPageID != session?.page?.id {
            clearSelectionPreview(); selectionView?.clearSelection()
        }
        selectionPageID = session?.page?.id
        if !enabled { selectionView?.removeFromSuperview(); selectionView = nil; return }
        if selectionView == nil { let overlay = PageSelectionView(); selectionView = overlay; addSubview(overlay) }
        selectionView?.frame = bounds
        selectionView?.immediate = immediate
        selectionView?.shape = shape
        selectionView?.moveBegan = { [weak self, weak session] path in
            guard let self, let session, let page = session.page else { return }
            self.clearSelectionPreview()
            let snapshot = SelectionMoveSnapshot(page: page, drawing: self.canvas.drawing,
                                                 path: self.logicalPath(path), settings: session.toolSettings)
            guard !snapshot.isEmpty, self.canvas.zoomScale > 0 else { return }
            let preview = SelectionDragPreview(frame: self.bounds, page: page, artwork: session.artwork,
                                               drawing: self.canvas.drawing, snapshot: snapshot,
                                               zoom: self.canvas.zoomScale, offset: self.canvas.contentOffset)
            self.selectionPreview = preview
            if let overlay = self.selectionView { self.insertSubview(preview, belowSubview: overlay) }
        }
        selectionView?.moveChanged = { [weak self] delta in self?.selectionPreview?.move(by: delta) ?? .zero }
        selectionView?.moveCancelled = { [weak self] in self?.clearSelectionPreview() }
        selectionView?.moved = moved.map { moved in
            { [weak self] path, delta in
                guard let self else { return }
                let pagePath = self.logicalPath(path)
                let logicalDelta = CGPoint(x: delta.x / self.canvas.zoomScale, y: delta.y / self.canvas.zoomScale)
                let preview = self.selectionPreview
                self.selectionCommitting = true; self.selectionRendered = false
                self.selectionView?.isUserInteractionEnabled = false
                Task { @MainActor [weak self] in
                    let success = await moved(pagePath, logicalDelta)
                    guard let self, self.selectionPreview === preview else { return }
                    self.selectionCommitFinished = true
                    if !success || logicalDelta == .zero || preview?.snapshot.ink.strokes.isEmpty != false || self.selectionRendered {
                        self.clearSelectionPreview()
                    }
                }
            }
        }
        selectionView?.pasteMenuRequested = { [weak self] point in
            self?.pasteMenu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: point))
        }
        selectionView?.pasteRequested = { [weak self] point in self?.requestPaste(at: point) }
        selectionView?.selected = { [weak self] rect, path, action in
            guard let self else { return }
            let logical = CGRect(x: (rect.minX + self.canvas.contentOffset.x) / self.canvas.zoomScale,
                                 y: (rect.minY + self.canvas.contentOffset.y) / self.canvas.zoomScale,
                                 width: rect.width / self.canvas.zoomScale, height: rect.height / self.canvas.zoomScale)
                .intersection(CGRect(origin: .zero, size: self.pageSize))
            if !logical.isNull {
                selected?(logical, self.logicalPath(path), action)
            }
        }
        if let selectionView { bringSubviewToFront(selectionView) }
    }
    private func logicalPath(_ path: UIBezierPath) -> UIBezierPath {
        let result = UIBezierPath(cgPath: path.cgPath), zoom = canvas.zoomScale
        result.apply(CGAffineTransform(a: 1 / zoom, b: 0, c: 0, d: 1 / zoom, tx: canvas.contentOffset.x / zoom, ty: canvas.contentOffset.y / zoom))
        return result
    }
    func configureNotes(_ page: NotePage, edit: ((PageElement) -> Void)?, changed: @escaping (PageElement?, UUID) -> Void) {
        guard notesPage?.id != page.id || notesPage.map(PageRenderer.size) != PageRenderer.size(page) ||
                notesPage?.elements?.filter({ $0.kind == .stickyNote }) != page.elements?.filter({ $0.kind == .stickyNote }) else { return }
        notesPage = page
        noteViews.forEach { $0.removeFromSuperview() }; noteViews = []
        for item in page.elements ?? [] where item.kind == .stickyNote {
            let control = StickyNoteControl(item: item)
            control.pageSize = pageSize; control.changed = { changed($0, item.id) }; control.edit = { edit?(item) }
            noteViews.append(control); addSubview(control)
        }
        alignBackground()
    }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        guard selectionView == nil, hit === canvas || hit?.isDescendant(of: canvas) == true else { return hit }
        for image in imageViews.reversed() {
            if let target = image.hitTest(convert(point, to: image), with: event) { return target }
        }
        return hit
    }
    var onPaste: ((CGPoint) -> Void)?
    lazy var pasteMenu = UIEditMenuInteraction(delegate: self)
    var onWindowReady: (() -> Void)?
    override func didMoveToWindow() { super.didMoveToWindow(); onWindowReady?() }
    @objc private func windowBecameKey(_ notification: Notification) {
        if let ready = notification.object as? UIWindow, ready === window { onWindowReady?() }
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    var onNavigate: ((Int) async -> Bool)?
    var verticalPaging = false
    private let fitGesture = UITapGestureRecognizer()
    private let backgroundTap = UITapGestureRecognizer()
    private let pasteHold = UILongPressGestureRecognizer()
    let touchObserver = CanvasTouchObserver()
    func detachInteractions() {
        pinchOrigin = nil
        for gesture in [touchObserver, fitGesture, pasteHold] { gesture.view?.removeGestureRecognizer(gesture) }
        zoomGesture.removeTarget(self, action: #selector(pinchChanged(_:)))
        removeGestureRecognizer(zoomGesture)
        if canvas.superview === self { canvas.pinchGestureRecognizer?.isEnabled = true }
        touchObserver.erased = nil; touchObserver.held = nil; touchObserver.beganStroke = nil; touchObserver.holdCancelled = nil; touchObserver.cancelledStroke = nil
        touchObserver.sampled = nil; touchObserver.adjustedShape = nil; touchObserver.eraserPointer = nil
        showEraserCursor(at: nil)
        clearShapePreview(); clearSelectionPreview()
    }
    var fingerDrawing = false {
        didSet {
            guard oldValue != fingerDrawing else { return }
            fitGesture.numberOfTouchesRequired = fingerDrawing ? 2 : 1
            pageTurn.gesture.minimumNumberOfTouches = fingerDrawing ? 2 : 1
            pageTurn.gesture.maximumNumberOfTouches = fingerDrawing ? 2 : 1
        }
    }
    private var positionKey: String?
    private var savedPosition: [Double]?
    static func restoredZoom(_ saved: [Double]?, fit: CGFloat) -> CGFloat? {
        guard let saved, (3...4).contains(saved.count), saved.allSatisfy(\.isFinite), saved[0] > 0 else { return nil }
        return saved.count == 4 && abs(saved[0] - saved[3]) < 0.02 ? fit : CGFloat(saved[0])
    }
    func restorePosition(_ id: UUID, noteID: UUID) {
        pinchOrigin = nil
        savePosition()
        positionKey = "viewport-\(noteID)-\(id)"
        let saved = UserDefaults.standard.array(forKey: positionKey!) as? [Double]
        savedPosition = Self.restoredZoom(saved, fit: canvas.minimumZoomScale) == nil ? nil : saved
    }
    func savePosition() {
        guard let positionKey, !needsFit, canvas.zoomScale > 0 else { return }
        UserDefaults.standard.set([Double(canvas.zoomScale), Double((canvas.contentOffset.x + bounds.width / 2) / canvas.zoomScale), Double((canvas.contentOffset.y + bounds.height / 2) / canvas.zoomScale), Double(canvas.minimumZoomScale)], forKey: positionKey)
    }
    @objc private func doubleTap(_ gesture: UITapGestureRecognizer) {
        toggleFit(at: gesture.location(in: self))
    }
    var widthFitZoom: CGFloat {
        min(canvas.maximumZoomScale, max(canvas.minimumZoomScale, (bounds.width - 32) / pageSize.width))
    }
    var heightFitZoom: CGFloat {
        min(canvas.maximumZoomScale, max(canvas.minimumZoomScale, (bounds.height - 32) / pageSize.height))
    }
    func toggleFit(at point: CGPoint) {
        let atWidth = abs(canvas.zoomScale - widthFitZoom) <= max(0.002, widthFitZoom * 0.015)
        fitAxis(horizontal: !atWidth, at: point)
    }
    func fitAxis(horizontal: Bool, at point: CGPoint? = nil) {
        guard pageSize.width > 0, pageSize.height > 0 else { return }
        pinchOrigin = nil
        let anchor = point ?? CGPoint(x: bounds.midX, y: bounds.midY)
        let logical = CGPoint(x: (anchor.x + canvas.contentOffset.x) / canvas.zoomScale,
                              y: (anchor.y + canvas.contentOffset.y) / canvas.zoomScale)
        let zoom = horizontal ? widthFitZoom : heightFitZoom
        let update = {
            self.canvas.setZoomScale(zoom, animated: false)
            self.alignBackground()
            self.canvas.contentOffset = self.boundedOffset(CGPoint(
                x: horizontal ? -self.canvas.contentInset.left : logical.x * zoom - anchor.x,
                y: horizontal ? logical.y * zoom - anchor.y : -self.canvas.contentInset.top))
        }
        if UIAccessibility.isReduceMotionEnabled { update() }
        else { UIView.animate(withDuration: 0.22, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut], animations: update) }
        savePosition()
    }
    @objc func fitPage() {
        let fit = max(0.1, min(4, (bounds.width - 32) / pageSize.width, (bounds.height - 32) / pageSize.height))
        let update = {
            self.canvas.setZoomScale(fit, animated: false)
            self.alignBackground()
            self.canvas.contentOffset = CGPoint(x: -self.canvas.contentInset.left, y: -self.canvas.contentInset.top)
        }
        if UIAccessibility.isReduceMotionEnabled { update() }
        else { UIView.animate(withDuration: 0.2, animations: update) }
        savePosition()
    }
    var pageSize = CGSize.zero
    var needsFit = true
    var initialZoom: CGFloat?
    private var viewportSize = CGSize.zero
    private var layingOut = false
    let zoomGesture = UIPinchGestureRecognizer()
    var isPinching: Bool { zoomGesture.state == .began || zoomGesture.state == .changed }
    private var pinchOrigin: (zoom: CGFloat, scale: CGFloat, point: CGPoint)?

    @objc private func pinchChanged(_ pinch: UIPinchGestureRecognizer) {
        // The parent receives touches over images too; PencilKit still owns zoom and ink rendering.
        let location = pinch.location(in: self)
        if pinch.state == .began {
            Diagnostics.shared.record("zoom.begin", ["scale": String(Double(canvas.zoomScale))])
            pinchOrigin = (canvas.zoomScale, pinch.scale, CGPoint(
                x: (canvas.contentOffset.x + location.x) / canvas.zoomScale,
                y: (canvas.contentOffset.y + location.y) / canvas.zoomScale))
        } else if pinch.state == .changed, let origin = pinchOrigin {
            let zoom = max(canvas.minimumZoomScale, min(canvas.maximumZoomScale, origin.zoom * pinch.scale / origin.scale))
            canvas.setZoomScale(zoom, animated: false)
            alignBackground()
            canvas.contentOffset = boundedOffset(CGPoint(x: origin.point.x * zoom - location.x, y: origin.point.y * zoom - location.y))
        } else if pinch.state == .ended || pinch.state == .cancelled || pinch.state == .failed {
            Diagnostics.shared.record("zoom.end", ["scale": String(Double(canvas.zoomScale))])
            pinchOrigin = nil; alignBackground(); savePosition()
        }
    }

    init(canvas: PKCanvasView) {
        self.canvas = canvas
        super.init(frame: .zero)
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(eraserHovered(_:)))
        hover.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        addGestureRecognizer(hover)
        NotificationCenter.default.addObserver(self, selector: #selector(windowBecameKey(_:)), name: UIWindow.didBecomeKeyNotification, object: nil)
        backgroundColor = .secondarySystemBackground
        clipsToBounds = true
        paper.backgroundColor = .white
        paper.isUserInteractionEnabled = false
        addSubview(paper)
        canvas.overrideUserInterfaceStyle = .light
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = true
        if #available(iOS 17.0, *) { canvas.maximumSupportedContentVersion = .version1 }
        canvas.minimumZoomScale = 0.1
        canvas.maximumZoomScale = 4
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.pinchGestureRecognizer?.isEnabled = false
        zoomGesture.addTarget(self, action: #selector(pinchChanged(_:)))
        zoomGesture.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        zoomGesture.delegate = self; addGestureRecognizer(zoomGesture)
        canvas.accessibilityLabel = "Handwriting page"
        canvas.accessibilityIdentifier = "editor.canvas"
        addSubview(canvas)
        compositedInk.isHidden = true; addSubview(compositedInk)
        liveInk.isHidden = true; addSubview(liveInk)
        canvas.addGestureRecognizer(touchObserver)
        canvas.panGestureRecognizer.require(toFail: touchObserver)
        backgroundTap.addTarget(self, action: #selector(tappedBackground(_:)))
        backgroundTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        backgroundTap.cancelsTouchesInView = false; backgroundTap.delegate = self
        addGestureRecognizer(backgroundTap)
        fitGesture.addTarget(self, action: #selector(doubleTap(_:)))
        fitGesture.numberOfTapsRequired = 2
        fitGesture.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        fitGesture.delegate = self; addGestureRecognizer(fitGesture)
        pasteHold.addTarget(self, action: #selector(showPasteMenu(_:)))
        pasteHold.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        pasteHold.delegate = self
        canvas.addGestureRecognizer(pasteHold); addInteraction(pasteMenu)
        canvas.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Fit width") { [weak self] _ in self?.fitAxis(horizontal: true); return true },
            UIAccessibilityCustomAction(name: "Fit height") { [weak self] _ in self?.fitAxis(horizontal: false); return true },
            UIAccessibilityCustomAction(name: "Paste at page center") { [weak self] _ in
            guard let self else { return false }
            self.onPaste?(CGPoint(x: self.pageSize.width / 2, y: self.pageSize.height / 2)); return true
        }]
        _ = pageTurn
        canvas.panGestureRecognizer.require(toFail: pageTurn.gesture)
        searchLayer.fillColor = UIColor.systemYellow.withAlphaComponent(0.35).cgColor
        searchLayer.strokeColor = UIColor.systemOrange.cgColor
        layer.addSublayer(searchLayer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, pageSize.width > 0, pageSize.height > 0 else { return }
        if viewportSize != .zero && viewportSize != bounds.size { pinchOrigin = nil; pageTurn.clear() }
        let oldCenter = CGPoint(x: (canvas.contentOffset.x + canvas.bounds.width / 2) / canvas.zoomScale, y: (canvas.contentOffset.y + canvas.bounds.height / 2) / canvas.zoomScale)
        let oldZoom = canvas.zoomScale
        let wasAtFit = abs(oldZoom - canvas.minimumZoomScale) < 0.02
        let firstFit = needsFit
        layingOut = true
        if canvas.frame != bounds { canvas.frame = bounds }
        if needsFit || viewportSize != bounds.size {
            Diagnostics.shared.record("viewport.layout", ["width": String(Double(bounds.width)), "height": String(Double(bounds.height)), "zoom": String(Double(oldZoom)), "fitted": String(wasAtFit), "first": String(firstFit)])
            needsFit = false
            viewportSize = bounds.size
            canvas.setZoomScale(1, animated: false)
            canvas.contentSize = pageSize
            let fit = max(0.1, min(4, (bounds.width - 32) / pageSize.width, (bounds.height - 32) / pageSize.height))
            canvas.minimumZoomScale = fit
            let restored = firstFit ? Self.restoredZoom(savedPosition, fit: fit) : (wasAtFit ? fit : oldZoom)
            canvas.setZoomScale(max(fit, min(4, initialZoom ?? restored ?? fit)), animated: false)
            canvas.layoutIfNeeded()
            layingOut = false
            alignBackground()
            if firstFit, let savedPosition {
                canvas.contentOffset = CGPoint(x: savedPosition[1] * canvas.zoomScale - bounds.width / 2, y: savedPosition[2] * canvas.zoomScale - bounds.height / 2)
            } else if !firstFit && !wasAtFit {
                canvas.contentOffset = CGPoint(x: oldCenter.x * canvas.zoomScale - bounds.width / 2, y: oldCenter.y * canvas.zoomScale - bounds.height / 2)
            } else { canvas.contentOffset = CGPoint(x: -canvas.contentInset.left, y: -canvas.contentInset.top) }
            canvas.contentOffset = boundedOffset(canvas.contentOffset)
        }
        layingOut = false
        alignBackground()
    }
    func boundedOffset(_ proposed: CGPoint) -> CGPoint {
        let minimum = CGPoint(x: -canvas.contentInset.left, y: -canvas.contentInset.top)
        return CGPoint(
            x: min(max(minimum.x, proposed.x), max(minimum.x, pageSize.width * canvas.zoomScale - bounds.width + canvas.contentInset.right)),
            y: min(max(minimum.y, proposed.y), max(minimum.y, pageSize.height * canvas.zoomScale - bounds.height + canvas.contentInset.bottom)))
    }
    func alignBackground() {
        guard !layingOut, pageSize.width > 0 else { return }
        canvas.accessibilityValue = "Zoom \(Int((canvas.zoomScale / max(0.01, canvas.minimumZoomScale) * 100).rounded())) %"
        let size = CGSize(width: pageSize.width * canvas.zoomScale, height: pageSize.height * canvas.zoomScale)
        let horizontal = max(0, (bounds.width - size.width) / 2)
        let vertical = max(0, (bounds.height - size.height) / 2)
        let inset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        if canvas.contentInset != inset { canvas.contentInset = inset }
        // Keep tile coordinates stable throughout a pinch; only the transform changes.
        paper.bounds = CGRect(origin: .zero, size: pageSize)
        paper.transform = CGAffineTransform(scaleX: canvas.zoomScale, y: canvas.zoomScale)
        paper.center = CGPoint(x: -canvas.contentOffset.x + size.width / 2, y: -canvas.contentOffset.y + size.height / 2)
        compositedInk.bounds = paper.bounds; compositedInk.transform = paper.transform; compositedInk.center = paper.center
        let path = UIBezierPath()
        for rect in searchRects {
            path.append(UIBezierPath(rect: CGRect(x: rect.minX * canvas.zoomScale - canvas.contentOffset.x, y: rect.minY * canvas.zoomScale - canvas.contentOffset.y, width: rect.width * canvas.zoomScale, height: rect.height * canvas.zoomScale)))
        }
        searchLayer.path = path.cgPath
        for note in noteViews {
            note.zoom = canvas.zoomScale
            let width = note.item.collapsed == true ? 44 : note.item.width
            let height = note.item.collapsed == true ? 44 : note.item.height
            note.frame = CGRect(x: note.item.x * canvas.zoomScale - canvas.contentOffset.x, y: note.item.y * canvas.zoomScale - canvas.contentOffset.y, width: max(44, width * canvas.zoomScale), height: max(44, height * canvas.zoomScale))
            note.titleLabel?.font = .systemFont(ofSize: max(12, 16 * canvas.zoomScale))
        }
        selectionView?.frame = bounds
        if let selectionView { bringSubviewToFront(selectionView) }
        for view in imageViews {
            view.zoom = canvas.zoomScale
            view.frame = CGRect(x: view.item.x * canvas.zoomScale - canvas.contentOffset.x, y: view.item.y * canvas.zoomScale - canvas.contentOffset.y, width: view.item.width * canvas.zoomScale, height: view.item.height * canvas.zoomScale)
        }
    }
}

extension PageScrollView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === backgroundTap else { return true }
        guard selectionView == nil else { return false }
        var target = touch.view
        while let view = target, view !== self {
            if view is ImageHandlesView || view is StickyNoteControl { return false }
            target = view.superview
        }
        return true
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
}

// The page is captured once; only the current stroke is rasterized on display frames.
final class LiveInkPreview: UIView {
    var stroke: PKStroke? { didSet { setNeedsDisplay() } }
    private var background: UIImage?
    private var foreground: UIImage?
    private var visibleRect = CGRect.zero
    private var zoom: CGFloat = 1
    private var offset = CGPoint.zero
    private var multiply = false
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false; isOpaque = false
        contentMode = .redraw
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func begin(page: NotePage, artwork: PageArtwork?, previous: PKDrawing, canvas: PKCanvasView) {
        zoom = max(0.01, canvas.zoomScale); offset = canvas.contentOffset
        visibleRect = CGRect(x: offset.x / zoom, y: offset.y / zoom, width: bounds.width / zoom, height: bounds.height / zoom)
            .intersection(CGRect(origin: .zero, size: PageRenderer.size(page)))
        multiply = artwork?.pdfPage != nil && (canvas.tool as? PKInkingTool)?.inkType == .marker
        guard bounds.width > 0, bounds.height > 0, !visibleRect.isNull else { return }
        var page = page; page.elements?.removeAll { $0.kind == .stickyNote }
        let format = UIGraphicsImageRendererFormat(); format.scale = min(2, contentScaleFactor); format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        var basePage = page
        if multiply { basePage.elements?.removeAll { $0.kind != .highlight }; basePage.text = nil }
        let baseDrawing = multiply ? PKDrawing(strokes: previous.strokes.filter { $0.ink.inkType == .marker }) : previous
        background = renderer.image { output in
            let context = output.cgContext
            context.translateBy(x: -offset.x, y: -offset.y); context.scaleBy(x: zoom, y: zoom)
            context.clip(to: visibleRect)
            PageRenderer.composite(basePage, data: artwork?.data, drawing: baseDrawing, resources: artwork?.resources ?? [:],
                                   context: context, pdfPage: artwork?.pdfPage, images: artwork?.images ?? [:],
                                   inkScale: zoom * format.scale, inkRect: visibleRect)
        }
        foreground = multiply ? renderer.image { output in
            let context = output.cgContext
            context.translateBy(x: -offset.x, y: -offset.y); context.scaleBy(x: zoom, y: zoom)
            context.clip(to: visibleRect)
            PageRenderer.elements(page, resources: artwork?.resources ?? [:], context: context, images: artwork?.images ?? [:], drewPDF: true)
            PKDrawing(strokes: previous.strokes.filter { $0.ink.inkType != .marker })
                .paperImage(from: visibleRect, scale: zoom * format.scale).draw(in: visibleRect)
        } : nil
    }
    func clear() { background = nil; foreground = nil; stroke = nil }
    override func draw(_ rect: CGRect) {
        background?.draw(in: bounds)
        defer { foreground?.draw(in: bounds) }
        guard let stroke, !visibleRect.isNull, !visibleRect.isEmpty else { return }
        let inkRect = stroke.renderBounds.intersection(visibleRect)
        guard !inkRect.isNull, !inkRect.isEmpty else { return }
        let screenRect = CGRect(x: inkRect.minX * zoom - offset.x, y: inkRect.minY * zoom - offset.y,
                                width: inkRect.width * zoom, height: inkRect.height * zoom)
        PKDrawing(strokes: [stroke]).paperImage(from: inkRect, scale: zoom * min(2, contentScaleFactor))
            .draw(in: screenRect, blendMode: multiply && stroke.ink.inkType == .marker ? .multiply : .normal, alpha: 1)
    }
}
