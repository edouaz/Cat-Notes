import SwiftUI
import UIKit

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
    var prepare: ((Int) -> Void)?
    var addPage: ((Int) async -> Bool)?
    var navigate: ((Int) async -> Bool)?
    func makeCoordinator() -> Coordinator { Coordinator(session: session, zoomWindow: zoomWindow) }
    func makeUIView(context: Context) -> PageScrollView {
        let view = PageScrollView(canvas: context.coordinator.activeCanvas)
        context.coordinator.container = view
        view.canvas.delegate = context.coordinator
        view.canvas.inkDelegate = context.coordinator
        view.onWindowReady = { [weak coordinator = context.coordinator] in
            coordinator?.updateInteraction()
        }
        view.onNavigate = navigate
        return view
    }
    func updateUIView(_ view: PageScrollView, context: Context) {
        guard let page = session.page else { return }
        let canvas = view.canvas
        if view.pageSize != PageRenderer.size(page) { view.savePosition(); view.pageSize = PageRenderer.size(page); view.needsFit = true; view.setNeedsLayout() }
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
        view.eraserCursorEnabled = !reading && !editingImages && !selecting && session.selectedTool == .eraser
        view.eraserCursorWidth = session.toolSettings.eraserWidth
        canvas.panGestureRecognizer.minimumNumberOfTouches = reading ? 1 : 2
        canvas.settings = session.toolSettings
        canvas.selectedTool = session.selectedTool
        canvas.onCommit = { [weak coordinator = context.coordinator] drawing, name in
            guard let coordinator, coordinator.pageID == coordinator.session.page?.id else { return }
            coordinator.session.replaceDrawing(drawing, actionName: name)
            if coordinator.zoomWindow { coordinator.activeCanvas.drawing = drawing }
        }
        canvas.onStrokeBegan = { [weak coordinator = context.coordinator] in coordinator?.circle = nil }
        canvas.onEstimatedStrokeUpdate = { [weak session] drawing in
            guard let session else { return }
            session.canvas.drawing = drawing
            session.changed(drawing)
        }
        canvas.onCompletedStroke = { [weak coordinator = context.coordinator] stroke in
            coordinator?.completed(stroke)
        }
        canvas.canCircleLongPress = { [weak coordinator = context.coordinator] point in coordinator?.canSelectCircle(at: point) == true }
        canvas.onCircleLongPress = { [weak coordinator = context.coordinator] point in
            guard let coordinator, coordinator.canSelectCircle(at: point), let circle = coordinator.circle else { return false }
            coordinator.circle = nil
            coordinator.session.replaceDrawing(InkDrawing(strokes: coordinator.session.drawing.strokes.filter { $0.id != circle.id }), actionName: "Circle to lasso")
            coordinator.session.selectedTool = .lasso
            coordinator.container?.configureSelection(true, session: coordinator.session, immediate: false,
                shape: coordinator.session.toolSettings.lassoShape, moved: selectionMoved, selected: selectedRect)
            coordinator.container?.installCircleSelection(circle.contour)
            return true
        }
        view.configureSelection(selecting, session: session, immediate: immediateSelection, shape: session.toolSettings.lassoShape, moved: selectionMoved, selected: selectedRect)
        view.onPaste = { point in Task { await session.paste(at: point); pasted?() } }
        view.verticalPaging = verticalPaging
        view.fingerDrawing = finger
        canvas.tool = session.tool
        canvas.isRulerActive = session.toolSettings.rulerEnabled == true && !reading && !editingImages && !selecting
        canvas.drawingPolicy = finger ? .anyInput : .pencilOnly
        canvas.drawingGestureRecognizer.isEnabled = !reading && !editingImages && !selecting
        if finger && !reading { view.pageTurn.disabled = true }
        if context.coordinator.pageID != page.id {
            canvas.cancelActiveStroke()
            context.coordinator.circle = nil
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
        // Native ink and previews share one renderer throughout the gesture.
        view.layoutIfNeeded()
        view.pageTurn.pageInstalled(page.id)
    }
    static func dismantleUIView(_ view: PageScrollView, coordinator: Coordinator) {
        view.onWindowReady = nil
        view.canvas.cancelActiveStroke()
        view.canvas.onCommit = nil; view.canvas.onCompletedStroke = nil
        view.canvas.onStrokeBegan = nil; view.canvas.onEstimatedStrokeUpdate = nil
        view.canvas.canCircleLongPress = nil; view.canvas.onCircleLongPress = nil
        coordinator.container = nil
        view.pageTurn.detach()
        view.detachInteractions()
        view.savePosition()
        if view.canvas.delegate === coordinator { view.canvas.delegate = nil; view.canvas.inkDelegate = nil }
    }

    final class Coordinator: NSObject, InkCanvasViewDelegate {
        let session: EditorSession
        let zoomWindow: Bool
        let zoomCanvas = InkCanvasView()
        weak var container: PageScrollView?
        var activeCanvas: InkCanvasView { zoomWindow ? zoomCanvas : session.canvas }
        var pageID: UUID?
        var loading = false
        var reading = false
        var circle: (id: UUID, contour: [CGPoint], expires: TimeInterval)?
        init(session: EditorSession, zoomWindow: Bool) {
            self.session = session; self.zoomWindow = zoomWindow
            super.init()
            for name in [Notification.Name.NSUndoManagerDidCloseUndoGroup, Notification.Name.NSUndoManagerDidUndoChange, Notification.Name.NSUndoManagerDidRedoChange] {
                NotificationCenter.default.addObserver(self, selector: #selector(undoHistoryChanged), name: name, object: session.canvas.undoManager)
            }
        }
        deinit { NotificationCenter.default.removeObserver(self) }
        @objc private func undoHistoryChanged() { updateUndoAvailability() }
        func updateInteraction() {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.container != nil else { return }
                if !self.reading && self.activeCanvas.window?.isKeyWindow == true { self.activeCanvas.becomeFirstResponder() }
                self.session.refreshUndoAvailability()
            }
        }
        func updateUndoAvailability() {
            DispatchQueue.main.async { [weak session] in session?.refreshUndoAvailability() }
        }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { activeCanvas.inkContentView }
        func scrollViewDidScroll(_ scrollView: UIScrollView) { container?.alignBackground() }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { container?.alignBackground() }
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { container?.savePosition() }
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) { if !decelerate { container?.savePosition() } }
        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) { container?.alignBackground(); container?.savePosition() }
        func canvasViewDrawingDidChange(_ canvas: InkCanvasView) { container?.selectionDidRender() }
        func canvasViewDidBeginUsingTool(_ canvas: InkCanvasView) {}
        func canvasViewDidEndUsingTool(_ canvas: InkCanvasView) { updateUndoAvailability() }
        func canvasViewDidFinishRendering(_ canvas: InkCanvasView) { container?.selectionDidRender() }
        func completed(_ stroke: InkStroke) -> InkDrawing? {
            let previous = session.drawing
            circle = nil
            guard stroke.ink.inkType != .marker, stroke.ink.inkType != .pencil else { return nil }
            let raw = stroke.rawSamples.map { $0.location.applying(stroke.transform) }
            if InkGestureRecognition.isScribble(raw, over: previous) {
                let erased = EraserEditing.erase(previous, along: raw, width: max(12, (stroke.style?.width ?? 3) * 3), mode: .pixel)
                if erased.dataRepresentation() != previous.dataRepresentation() { return erased }
            }
            if InkGestureRecognition.circle(raw) != nil {
                circle = (stroke.id, raw, ProcessInfo.processInfo.systemUptime + 4)
            }
            return nil
        }
        func canSelectCircle(at point: CGPoint) -> Bool {
            guard [.pen, .fountainPen].contains(session.selectedTool),
                  let circle, circle.expires > ProcessInfo.processInfo.systemUptime,
                  pageID == session.page?.id, session.drawing.strokes.contains(where: { $0.id == circle.id }) else { return false }
            return InkGestureRecognition.isOnContour(point, contour: circle.contour, tolerance: 12 / max(0.1, activeCanvas.zoomScale))
        }
    }
}

// The viewport keeps the existing page coordinate transform and navigation.
final class PageScrollView: UIView {
    let canvas: InkCanvasView
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
    private var imageViews: [ImageHandlesView] = []
    private var imagePage: NotePage?
    private var editingImages = false
    var onImageEditingEnded: (() -> Void)?
    private func selectImage(_ id: UUID?) { imageViews.forEach { $0.showsHandles = $0.item.id == id } }
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
    func installCircleSelection(_ contour: [CGPoint]) {
        guard let first = contour.first else { return }
        let path = UIBezierPath(); path.move(to: first)
        for point in contour.dropFirst() { path.addLine(to: point) }
        path.close()
        path.apply(CGAffineTransform(a: canvas.zoomScale, b: 0, c: 0, d: canvas.zoomScale, tx: -canvas.contentOffset.x, ty: -canvas.contentOffset.y))
        selectionView?.installSelection(path)
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
    func detachInteractions() {
        pinchOrigin = nil
        for gesture in [fitGesture, pasteHold] { gesture.view?.removeGestureRecognizer(gesture) }
        zoomGesture.removeTarget(self, action: #selector(pinchChanged(_:)))
        removeGestureRecognizer(zoomGesture)
        if canvas.superview === self { canvas.pinchGestureRecognizer?.isEnabled = true }
        showEraserCursor(at: nil)
        clearSelectionPreview()
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
        // The parent receives touches over images too; the native canvas owns ink rendering.
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

    init(canvas: InkCanvasView) {
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
            canvas.minimumZoomScale = 0.1
            canvas.setZoomScale(1, animated: false)
            canvas.setPageSize(pageSize)
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
