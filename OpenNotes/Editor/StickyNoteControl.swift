import UIKit

final class StickyNoteControl: UIButton {
    var item: PageElement
    var zoom: CGFloat = 1
    var pageSize = CGSize.zero
    var changed: ((PageElement?) -> Void)?
    var edit: (() -> Void)?
    let collapseButton = UIButton(type: .system)
    let resizeHandle = UIView()
    private var initialSize = CGSize.zero
    init(item: PageElement) {
        self.item = item
        super.init(frame: .zero)
        backgroundColor = UIColor(red: 1, green: 0.92, blue: 0.5, alpha: 1)
        setTitle(item.collapsed == true ? nil : item.text, for: .normal)
        setTitleColor(.black, for: .normal)
        titleLabel?.numberOfLines = 0; titleLabel?.font = .systemFont(ofSize: 16)
        titleLabel?.adjustsFontForContentSizeCategory = true
        accessibilityLabel = "Sticky note: \(item.text)"
        accessibilityValue = item.collapsed == true ? "Collapsed" : "Expanded"
        accessibilityCustomActions = [UIAccessibilityCustomAction(name: item.collapsed == true ? "Expand" : "Collapse") { [weak self] _ in self?.toggleCollapsed(); return true }]
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        collapseButton.setImage(UIImage(systemName: item.collapsed == true ? "arrow.up.left.and.arrow.down.right" : "rectangle.compress.vertical"), for: .normal)
        collapseButton.tintColor = .darkGray; collapseButton.accessibilityLabel = item.collapsed == true ? "Expand sticky note" : "Collapse sticky note"
        collapseButton.addTarget(self, action: #selector(toggleCollapsed), for: .touchUpInside)
        addSubview(collapseButton)
        let symbol = UIImageView(image: UIImage(systemName: "arrow.down.right"))
        symbol.tintColor = .darkGray; symbol.frame = CGRect(x: 18, y: 18, width: 18, height: 18)
        resizeHandle.addSubview(symbol); resizeHandle.isHidden = item.collapsed == true
        let resizePan = UIPanGestureRecognizer(target: self, action: #selector(resize(_:)))
        resizeHandle.addGestureRecognizer(resizePan)
        addSubview(resizeHandle)
        menu = UIMenu(children: [
            UIAction(title: "Edit", image: UIImage(systemName: "pencil")) { [weak self] _ in self?.edit?() },
            UIAction(title: item.collapsed == true ? "Expand" : "Collapse", image: UIImage(systemName: "rectangle.compress.vertical")) { [weak self] _ in
                self?.toggleCollapsed()
            },
            UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.changed?(nil) }
        ])
        let dragPan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))
        dragPan.require(toFail: resizePan); addGestureRecognizer(dragPan)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        collapseButton.frame = CGRect(x: max(0, bounds.width - 44), y: 0, width: 44, height: 44)
        resizeHandle.frame = CGRect(x: max(0, bounds.width - 44), y: max(0, bounds.height - 44), width: 44, height: 44)
    }
    @objc func toggleCollapsed() { item.collapsed = !(item.collapsed ?? false); changed?(item) }
    func resizeNote(to size: CGSize) {
        item.width = min(max(88 / max(zoom, 0.01), size.width), pageSize.width - item.x)
        item.height = min(max(88 / max(zoom, 0.01), size.height), pageSize.height - item.y)
        changed?(item)
    }
    @objc private func resize(_ pan: UIPanGestureRecognizer) {
        if pan.state == .began { initialSize = frame.size }
        let delta = pan.translation(in: superview)
        if pan.state == .changed { frame.size = CGSize(width: max(88, initialSize.width + delta.x), height: max(88, initialSize.height + delta.y)) }
        if pan.state == .ended { resizeNote(to: CGSize(width: (initialSize.width + delta.x) / zoom, height: (initialSize.height + delta.y) / zoom)) }
        else if pan.state == .cancelled { frame.size = initialSize }
    }
    @objc private func tapped() {
        if item.collapsed == true { item.collapsed = false; changed?(item) }
        else { edit?() }
    }
    @objc private func drag(_ pan: UIPanGestureRecognizer) {
        let delta = pan.translation(in: superview)
        if pan.state == .changed { transform = CGAffineTransform(translationX: delta.x, y: delta.y) }
        if pan.state == .ended {
            item.x = min(max(0, item.x + delta.x / zoom), max(0, pageSize.width - item.width))
            item.y = min(max(0, item.y + delta.y / zoom), max(0, pageSize.height - item.height))
            transform = .identity; changed?(item)
        } else if pan.state == .cancelled { transform = .identity }
    }
}
