import UIKit

enum PageSelectionAction { case preview, copyPhoto, copyInk, enlarge, shrink, deleteContent, copySelection, cutSelection, duplicateSelection, lockSelection, collapseSelection, bringFront, sendBack, editText, recolorSelection, formatText }

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
    var transformChanged: ((CGFloat, CGFloat, CGFloat, CGPoint) -> Void)?
    var transformCommitted: ((UIBezierPath, CGFloat, CGFloat, CGFloat, CGPoint) -> Void)?
    var allowsFreeResize: ((UIBezierPath) -> Bool)?
    var directSelection: ((CGPoint) -> UIBezierPath?)?
    var menuActions: ((UIBezierPath) -> [UIMenuElement])?
    private var handles: [UIView] = []
    private var freeResizeAllowed = false
    private var transformOrigin = UIBezierPath()
    private var transformStart = CGPoint.zero
    private var pendingScale: CGFloat = 1
    private var pendingRotation: CGFloat = 0
    private var pendingScaleY: CGFloat = 1
    private var transformAnchor = CGPoint.zero
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
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        for index in 0..<9 {
            let handle = UIView(); handle.tag = index
            let dot = UIView(frame: CGRect(x: 17, y: 17, width: 10, height: 10))
            dot.backgroundColor = index >= 5 ? .systemBlue : .white; dot.layer.borderColor = UIColor.systemBlue.cgColor; dot.layer.borderWidth = 2
            dot.layer.cornerRadius = index >= 4 ? 5 : 1
            dot.isUserInteractionEnabled = false; handle.addSubview(dot)
            handle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(transformDragged(_:))))
            handle.accessibilityLabel = index == 4 ? "Rotate selection" : "Scale selection"
            handle.isHidden = true; addSubview(handle); handles.append(handle)
        }
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
    func clearSelection() { completed = false; path = UIBezierPath(); outline.path = nil; handles.forEach { $0.isHidden = true }; editMenu.dismissMenu() }
    func installSelection(_ selection: UIBezierPath) {
        path = selection; completed = true; outline.path = path.cgPath
        freeResizeAllowed = allowsFreeResize?(path) == true
        updateHandles()
        presentMenu()
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
        if let menuActions { return UIMenu(children: menuActions(path)) }
        return UIMenu(children: [
            UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in self?.perform(.copySelection) },
            UIAction(title: "Cut", image: UIImage(systemName: "scissors")) { [weak self] _ in self?.perform(.cutSelection) },
            UIAction(title: "Duplicate", image: UIImage(systemName: "plus.square.on.square")) { [weak self] _ in self?.perform(.duplicateSelection) },
            UIAction(title: "Take Screenshot", image: UIImage(systemName: "camera")) { [weak self] _ in self?.perform(.preview) }
        ])
    }
    func action(_ title: String, symbol: String, kind: PageSelectionAction, destructive: Bool = false) -> UIAction {
        UIAction(title: title, image: UIImage(systemName: symbol), attributes: destructive ? .destructive : []) { [weak self] _ in self?.perform(kind) }
    }
    private func presentMenu() {
        guard completed, !immediate, window != nil else { return }
        let point = CGPoint(x: min(max(24, path.bounds.midX), bounds.width - 24), y: max(24, path.bounds.minY - 12))
        editMenu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: point))
    }
    private func updateHandles() {
        let rect = path.bounds
        let centers = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.midX, y: rect.minY - 30), CGPoint(x: rect.minX, y: rect.midY), CGPoint(x: rect.maxX, y: rect.midY), CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.midX, y: rect.maxY)]
        for (index, handle) in handles.enumerated() {
            handle.isHidden = !completed || immediate || (index >= 5 && !freeResizeAllowed)
            handle.frame = CGRect(x: centers[index].x - 22, y: centers[index].y - 22, width: 44, height: 44)
        }
    }
    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        if completed, path.contains(point) { presentMenu(); return }
        if let selected = directSelection?(point) { installSelection(selected) }
        else { clearSelection() }
    }
    @objc private func transformDragged(_ gesture: UIPanGestureRecognizer) {
        guard completed, let handle = gesture.view else { return }
        let point = gesture.location(in: self)
        if gesture.state == .began {
            transformOrigin = UIBezierPath(cgPath: path.cgPath); transformStart = point
            pendingScale = 1; pendingRotation = 0; editMenu.dismissMenu()
            moveBegan?(transformOrigin)
        }
        let rect = transformOrigin.bounds
        let center = CGPoint(x: rect.midX, y: rect.midY)
        if gesture.state == .began {
            if handle.tag == 4 || gesture.modifierFlags.contains(.alternate) { transformAnchor = center }
            else {
                let anchors = [CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.minX, y: rect.minY), center, CGPoint(x: rect.maxX, y: rect.midY), CGPoint(x: rect.minX, y: rect.midY), CGPoint(x: rect.midX, y: rect.maxY), CGPoint(x: rect.midX, y: rect.minY)]
                transformAnchor = anchors[handle.tag]
            }
        }
        if handle.tag == 4 {
            pendingRotation = atan2(point.y - center.y, point.x - center.x) - atan2(transformStart.y - center.y, transformStart.x - center.x)
            pendingScaleY = 1
        } else if handle.tag >= 5 {
            if handle.tag <= 6 {
                pendingScale = min(10, max(0.1, abs(point.x - transformAnchor.x) / max(1, abs(transformStart.x - transformAnchor.x))))
                pendingScaleY = gesture.modifierFlags.contains(.shift) ? pendingScale : 1
            } else {
                pendingScaleY = min(10, max(0.1, abs(point.y - transformAnchor.y) / max(1, abs(transformStart.y - transformAnchor.y))))
                pendingScale = gesture.modifierFlags.contains(.shift) ? pendingScaleY : 1
            }
        } else {
            pendingScale = min(10, max(0.1, hypot(point.x - transformAnchor.x, point.y - transformAnchor.y) / max(1, hypot(transformStart.x - transformAnchor.x, transformStart.y - transformAnchor.y))))
            pendingScaleY = pendingScale
        }
        let a = cos(pendingRotation) * pendingScale, b = sin(pendingRotation) * pendingScale
        let c = -sin(pendingRotation) * pendingScaleY, d = cos(pendingRotation) * pendingScaleY
        let anchor = transformAnchor
        path = UIBezierPath(cgPath: transformOrigin.cgPath)
        path.apply(CGAffineTransform(a: a, b: b, c: c, d: d, tx: anchor.x - a * anchor.x - c * anchor.y, ty: anchor.y - b * anchor.x - d * anchor.y))
        outline.path = path.cgPath; updateHandles()
        transformChanged?(pendingScale, pendingScaleY, pendingRotation, anchor)
        if gesture.state == .ended {
            transformCommitted?(transformOrigin, pendingScale, pendingScaleY, pendingRotation, anchor)
            clearSelection()
        } else if gesture.state == .cancelled || gesture.state == .failed {
            moveCancelled?()
            path = transformOrigin; outline.path = path.cgPath; updateHandles()
        }
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
            updateHandles()
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
            freeResizeAllowed = completed && allowsFreeResize?(path) == true
            updateHandles()
            if completed && immediate { perform(.preview) }
            else if completed { presentMenu() }
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
    private let guides = CAShapeLayer()
    private var guidePosition: CGPoint?
    private let offset: CGPoint

    init(frame: CGRect, page: NotePage, artwork: PageArtwork?, drawing: InkDrawing,
         snapshot: SelectionMoveSnapshot, zoom: CGFloat, offset: CGPoint) {
        self.snapshot = snapshot; self.zoom = zoom; self.offset = offset
        super.init(frame: frame)
        isUserInteractionEnabled = false; clipsToBounds = true
        background.frame = bounds; addSubview(background); addSubview(foreground)
        guides.strokeColor = UIColor.systemBlue.cgColor; guides.lineWidth = 1; guides.lineDashPattern = [4, 4]; guides.fillColor = nil; layer.addSublayer(guides)
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
        let requested = CGPoint(x: screenDelta.x / zoom, y: screenDelta.y / zoom)
        // Keep a captured guide until the pointer leaves a wider release band.
        let tolerance: CGFloat = guidePosition == nil ? 5 : 8
        let result = snapshot.snap(requested, tolerance: tolerance / max(0.01, zoom))
        delta = result.0; guidePosition = result.1
        let guidePath = UIBezierPath()
        if let guidePosition {
            if guidePosition.x.isFinite {
                let x = guidePosition.x * zoom - offset.x
                guidePath.move(to: CGPoint(x: x, y: 0)); guidePath.addLine(to: CGPoint(x: x, y: bounds.height))
            }
            if guidePosition.y.isFinite {
                let y = guidePosition.y * zoom - offset.y
                guidePath.move(to: CGPoint(x: 0, y: y)); guidePath.addLine(to: CGPoint(x: bounds.width, y: y))
            }
        }
        guides.path = guidePath.cgPath
        let screen = CGPoint(x: delta.x * zoom, y: delta.y * zoom)
        foreground.transform = CGAffineTransform(translationX: screen.x, y: screen.y)
        return screen
    }
}
