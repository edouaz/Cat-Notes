import UIKit

extension PageScrollView: UIEditMenuInteractionDelegate {
    @objc func showPasteMenu(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: self)
        pasteMenu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: point))
    }
    func requestPaste(at point: CGPoint) {
        let logical = CGPoint(x: (point.x + canvas.contentOffset.x) / canvas.zoomScale, y: (point.y + canvas.contentOffset.y) / canvas.zoomScale)
        onPaste?(logical)
    }
    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
        let point = configuration.sourcePoint
        let clipboard = UIPasteboard.general
        let available = clipboard.contains(pasteboardTypes: [DocumentClipboard.inkType]) || clipboard.hasImages || clipboard.hasStrings
        return UIMenu(children: [UIAction(title: "Coller", image: UIImage(systemName: "doc.on.clipboard"), attributes: available ? [] : .disabled) { [weak self] _ in self?.requestPaste(at: point) }])
    }
}
