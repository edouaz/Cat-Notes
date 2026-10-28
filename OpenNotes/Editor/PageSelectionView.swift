import UIKit

enum PageSelectionAction { case preview, copyPhoto, copyInk, enlarge, shrink, deleteContent }

final class PageSelectionView: UIView, UIEditMenuInteractionDelegate {
    var selected: ((CGRect, UIBezierPath, PageSelectionAction) -> Void)?
    var immediate = false
    var shape = EditorToolSettings.LassoShape.freeform
    var moveBegan: ((UIBezierPath) -> Void)?
    var moveChanged: ((CGPoint) -> CGPoint)?
    var moveCancelled: (() -> Void)?
    var moved: ((UIBezierPath, CGPoint) -> Void)?
    var pasteMenuRequested: ((CGPoint) -> Void)?
    var pasteRequested: ((CGPoint) -> Void)?
    private var path = UIBezierPath()
    private var completed = false
    private var start = CGPoint.zero
    private var moving = false
    private var originalPath = UIBezierPath()
    private let outline = CAShapeLayer()
    private lazy var editMenu = UIEditMenuInteraction(delegate: self)
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        outline.fillColor = UIColor.systemBlue.withAlphaComponent(0.12).cgColor
        outline.strokeColor = UIColor.systemBlue.cgColor; outline.lineWidth = 2; outline.lineDashPattern = [6, 4]
        layer.addSublayer(outline)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        addGestureRecognizer(hold); addInteraction(editMenu)
        isAccessibilityElement = true
        accessibilityLabel = "Area selection"
        accessibilityHint = "Outline an area, then move its contents or long press inside to copy strokes or capture an image."
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Enlarge selection") { [weak self] _ in self?.perform(.enlarge); return true },
            UIAccessibilityCustomAction(name: "Shrink selection") { [weak self] _ in self?.perform(.shrink); return true },
            UIAccessibilityCustomAction(name: "Delete selection") { [weak self] _ in self?.perform(.deleteContent); return true },
            UIAccessibilityCustomAction(name: "Copy image") { [weak self] _ in self?.perform(.copyPhoto); return true },
            UIAccessibilityCustomAction(name: "Copy strokes") { [weak self] _ in self?.perform(.copyInk); return true },
            UIAccessibilityCustomAction(name: "Share image") { [weak self] _ in self?.perform(.preview); return true }
        ]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func clearSelection() { completed = false; path = UIBezierPath(); outline.path = nil; editMenu.dismissMenu() }
    func installSelection(_ selection: UIBezierPath) {
        path = selection; completed = true; outline.path = path.cgPath
    }
    private func perform(_ action: PageSelectionAction) {
        guard completed else { return }
        selected?(path.bounds.intersection(bounds), path, action)
    }
    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        let point = gesture.location(in: self)
        guard gesture.state == .began else { return }
        if completed && path.contains(point) {
            editMenu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: point))
        } else { pasteMenuRequested?(point) }
    }
    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
        UIMenu(children: [
            UIAction(title: "Enlarge by 10%", image: UIImage(systemName: "arrow.up.left.and.arrow.down.right")) { [weak self] _ in self?.perform(.enlarge) },
            UIAction(title: "Shrink by 10%", image: UIImage(systemName: "arrow.down.right.and.arrow.up.left")) { [weak self] _ in self?.perform(.shrink) },
            UIAction(title: "Delete selection", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.perform(.deleteContent) },
            UIAction(title: "Image: copy", image: UIImage(systemName: "camera")) { [weak self] _ in self?.perform(.copyPhoto) },
            UIAction(title: "Image: share…", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in self?.perform(.preview) },
            UIAction(title: "Copy strokes only", image: UIImage(systemName: "pencil.tip")) { [weak self] _ in self?.perform(.copyInk) },
            UIAction(title: "Paste", image: UIImage(systemName: "doc.on.clipboard")) { [weak self] _ in self?.pasteRequested?(configuration.sourcePoint) }
        ])
    }
    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        updateDrag(state: gesture.state, point: gesture.location(in: self), translation: gesture.translation(in: self))
    }
    func updateDrag(state: UIGestureRecognizer.State, point: CGPoint, translation: CGPoint) {
        if state == .began {
            moveCancelled?()
            editMenu.dismissMenu()
            // A pan begins only after crossing UIKit’s threshold. Hit-test the
            // contact origin: the current position may be outside a small lasso by then.
            start = CGPoint(x: point.x - translation.x, y: point.y - translation.y)
            moving = completed && path.contains(start) && moved != nil && !immediate
            if moving { originalPath = UIBezierPath(cgPath: path.cgPath); moveBegan?(originalPath) }
            else { completed = false; path = UIBezierPath(); path.move(to: start) }
        }
        if moving {
            let requested = translation
            let delta = moveChanged?(requested) ?? requested
            path = UIBezierPath(cgPath: originalPath.cgPath); path.apply(CGAffineTransform(translationX: delta.x, y: delta.y))
            outline.path = path.cgPath
            if state == .ended { moved?(originalPath, delta); moving = false; clearSelection() }
            else if state == .cancelled || state == .failed { moveCancelled?(); path = originalPath; outline.path = path.cgPath; moving = false }
            return
        }
        if shape == .rectangle { path = UIBezierPath(rect: CGRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x), height: abs(point.y - start.y))) }
        else { path.addLine(to: point) }
        outline.path = path.cgPath
        if state == .ended {
            path.close()
            let rect = path.bounds.intersection(bounds)
            completed = !rect.isNull && rect.width >= 8 && rect.height >= 8
            outline.path = completed ? path.cgPath : nil
            if completed && immediate { perform(.preview) }
        } else if state == .cancelled || state == .failed { completed = false; outline.path = nil }
    }
}

// Rasterize only at pickup. During dragging, UIKit translates the cached foreground.
final class SelectionDragPreview: UIView {
    let background = UIImageView()
    let foreground = UIImageView()
    let snapshot: SelectionMoveSnapshot
    let zoom: CGFloat
    private(set) var delta = CGPoint.zero

    init(frame: CGRect, page: NotePage, artwork: PageArtwork?, drawing: InkDrawing,
         snapshot: SelectionMoveSnapshot, zoom: CGFloat, offset: CGPoint) {
        self.snapshot = snapshot; self.zoom = zoom
        super.init(frame: frame)
        isUserInteractionEnabled = false; clipsToBounds = true
        background.frame = bounds; addSubview(background); addSubview(foreground)
        let visible = CGRect(x: offset.x / zoom, y: offset.y / zoom, width: bounds.width / zoom, height: bounds.height / zoom)
            .intersection(CGRect(origin: .zero, size: snapshot.pageSize))
        guard !visible.isNull, !snapshot.isEmpty else { return }
        var base = page; base.elements?.removeAll { snapshot.elementIDs.contains($0.id) }
        let remaining = InkDrawing(strokes: drawing.strokes.enumerated().filter { !snapshot.strokeIndices.contains($0.offset) }.map(\.element))
        let format = UIGraphicsImageRendererFormat(); format.scale = min(2, traitCollection.displayScale)
        background.image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { output in
            let context = output.cgContext
            context.translateBy(x: -offset.x, y: -offset.y); context.scaleBy(x: zoom, y: zoom)
            context.clip(to: visible)
            // Match the on-screen stack: paper/elements, then native translucent ink.
            PageRenderer.background(base, data: artwork?.data, resources: artwork?.resources ?? [:],
                                    context: context, pdfPage: artwork?.pdfPage, images: artwork?.images ?? [:])
            remaining.paperImage(from: visible, scale: zoom * format.scale).draw(in: visible)
        }
        let crop = snapshot.bounds.insetBy(dx: -2, dy: -2)
        let scale = min(zoom * format.scale, 4096 / max(crop.width, crop.height))
        let ink = snapshot.ink.paperImage(from: crop, scale: scale)
        var selectedPage = page; selectedPage.elements = snapshot.elements; selectedPage.text = nil
        let foregroundFormat = UIGraphicsImageRendererFormat(); foregroundFormat.scale = scale; foregroundFormat.opaque = false
        foreground.image = UIGraphicsImageRenderer(size: crop.size, format: foregroundFormat).image { output in
            output.cgContext.translateBy(x: -crop.minX, y: -crop.minY)
            PageRenderer.elements(selectedPage, resources: artwork?.resources ?? [:], context: output.cgContext,
                                  images: artwork?.images ?? [:], drewPDF: false)
            ink.draw(in: crop)
        }
        foreground.frame = CGRect(x: crop.minX * zoom - offset.x, y: crop.minY * zoom - offset.y,
                                  width: crop.width * zoom, height: crop.height * zoom)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @discardableResult
    func move(by screenDelta: CGPoint) -> CGPoint {
        delta = snapshot.clamped(CGPoint(x: screenDelta.x / zoom, y: screenDelta.y / zoom))
        let screen = CGPoint(x: delta.x * zoom, y: delta.y * zoom)
        foreground.transform = CGAffineTransform(translationX: screen.x, y: screen.y)
        return screen
    }
}
