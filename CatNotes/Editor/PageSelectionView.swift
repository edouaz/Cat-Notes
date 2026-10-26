import UIKit

enum PageSelectionAction { case preview, copyPhoto, copyInk, enlarge, shrink, deleteContent }

final class PageSelectionView: UIView, UIEditMenuInteractionDelegate {
    var selected: ((CGRect, UIBezierPath, PageSelectionAction) -> Void)?
    var immediate = false
    var shape = EditorToolSettings.LassoShape.freeform
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
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(drag(_:))))
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        addGestureRecognizer(hold); addInteraction(editMenu)
        isAccessibilityElement = true
        accessibilityLabel = "Sélection de zone"
        accessibilityHint = "Tracez une zone, puis déplacez son contenu ou appuyez longuement à l’intérieur pour copier les traits ou capturer une photo."
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Agrandir la sélection") { [weak self] _ in self?.perform(.enlarge); return true },
            UIAccessibilityCustomAction(name: "Réduire la sélection") { [weak self] _ in self?.perform(.shrink); return true },
            UIAccessibilityCustomAction(name: "Supprimer la sélection") { [weak self] _ in self?.perform(.deleteContent); return true },
            UIAccessibilityCustomAction(name: "Copier la photo") { [weak self] _ in self?.perform(.copyPhoto); return true },
            UIAccessibilityCustomAction(name: "Copier les traits") { [weak self] _ in self?.perform(.copyInk); return true },
            UIAccessibilityCustomAction(name: "Partager la photo") { [weak self] _ in self?.perform(.preview); return true }
        ]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func clearSelection() { completed = false; path = UIBezierPath(); outline.path = nil; editMenu.dismissMenu() }
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
            UIAction(title: "Agrandir de 10 %", image: UIImage(systemName: "arrow.up.left.and.arrow.down.right")) { [weak self] _ in self?.perform(.enlarge) },
            UIAction(title: "Réduire de 10 %", image: UIImage(systemName: "arrow.down.right.and.arrow.up.left")) { [weak self] _ in self?.perform(.shrink) },
            UIAction(title: "Supprimer la sélection", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.perform(.deleteContent) },
            UIAction(title: "Photo : copier", image: UIImage(systemName: "camera")) { [weak self] _ in self?.perform(.copyPhoto) },
            UIAction(title: "Photo : partager…", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in self?.perform(.preview) },
            UIAction(title: "Copier uniquement les traits", image: UIImage(systemName: "pencil.tip")) { [weak self] _ in self?.perform(.copyInk) },
            UIAction(title: "Coller", image: UIImage(systemName: "doc.on.clipboard")) { [weak self] _ in self?.pasteRequested?(configuration.sourcePoint) }
        ])
    }
    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: self)
        if gesture.state == .began {
            editMenu.dismissMenu(); start = point
            moving = completed && path.contains(point) && moved != nil && !immediate
            if moving { originalPath = UIBezierPath(cgPath: path.cgPath) }
            else { completed = false; path = UIBezierPath(); path.move(to: point) }
        }
        if moving {
            let delta = gesture.translation(in: self)
            path = UIBezierPath(cgPath: originalPath.cgPath); path.apply(CGAffineTransform(translationX: delta.x, y: delta.y))
            outline.path = path.cgPath
            if gesture.state == .ended { moved?(originalPath, delta); moving = false; clearSelection() }
            else if gesture.state == .cancelled || gesture.state == .failed { path = originalPath; outline.path = path.cgPath; moving = false }
            return
        }
        if shape == .rectangle { path = UIBezierPath(rect: CGRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x), height: abs(point.y - start.y))) }
        else { path.addLine(to: point) }
        outline.path = path.cgPath
        if gesture.state == .ended {
            path.close()
            let rect = path.bounds.intersection(bounds)
            completed = !rect.isNull && rect.width >= 8 && rect.height >= 8
            outline.path = completed ? path.cgPath : nil
            if completed && immediate { perform(.preview) }
        } else if gesture.state == .cancelled || gesture.state == .failed { completed = false; outline.path = nil }
    }
}
