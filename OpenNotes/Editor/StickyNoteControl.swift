import UIKit

final class StickyNoteControl: UIButton, UITextViewDelegate {
    var item: PageElement
    var zoom: CGFloat = 1
    var pageSize = CGSize.zero
    var changed: ((PageElement?) -> Void)?
    var edit: (() -> Void)?
    var selectsBeforeEditing = false
    var inlineEditingChanged: ((Bool) -> Void)?
    var draftChanged: ((PageElement) -> Void)?
    let collapseButton = UIButton(type: .system)
    let resizeHandle = UIView()
    private var initialSize = CGSize.zero
    private var initialCenter = CGPoint.zero
    private var textEditor: UITextView?
    var isEditingInline: Bool { textEditor != nil }
    init(item: PageElement) {
        self.item = item
        super.init(frame: .zero)
        backgroundColor = .clear
        contentHorizontalAlignment = .left; contentVerticalAlignment = .top
        contentEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        setTitle(nil, for: .normal)
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
        collapseButton.isHidden = item.isLocked == true || item.collapsed == true
        addSubview(collapseButton)
        let symbol = UIImageView(image: UIImage(systemName: "arrow.down.right"))
        symbol.tintColor = .darkGray; symbol.frame = CGRect(x: 18, y: 18, width: 18, height: 18)
        resizeHandle.addSubview(symbol); resizeHandle.isHidden = item.collapsed == true || item.isLocked == true
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
        if item.isLocked == true {
            menu = UIMenu(children: [UIAction(title: "Unlock", image: UIImage(systemName: "lock.open")) { [weak self] _ in
                guard let self else { return }; self.item.isLocked = false; self.changed?(self.item)
            }])
            showsMenuAsPrimaryAction = true
        }
        let dragPan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))
        dragPan.require(toFail: resizePan); addGestureRecognizer(dragPan)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Pencil ink belongs to the existing canvas; a focused text editor keeps native Scribble.
        if textEditor == nil, event?.allTouches?.contains(where: { $0.type == .pencil }) == true { return nil }
        return super.hitTest(point, with: event)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        textEditor?.frame = bounds
        collapseButton.frame = CGRect(x: max(0, bounds.width - 44), y: 0, width: 44, height: 44)
        resizeHandle.frame = CGRect(x: max(0, bounds.width - 44), y: max(0, bounds.height - 44), width: 44, height: 44)
    }
    @objc func toggleCollapsed() { guard item.isLocked != true else { return }; item.collapsed = !(item.collapsed ?? false); changed?(item) }
    func resizeNote(to size: CGSize) {
        guard item.isLocked != true else { return }
        item.width = min(max(88 / max(zoom, 0.01), size.width), pageSize.width - item.x)
        item.height = min(max(88 / max(zoom, 0.01), size.height), pageSize.height - item.y)
        changed?(item)
    }
    @objc private func resize(_ pan: UIPanGestureRecognizer) {
        guard item.isLocked != true else { return }
        if pan.state == .began { initialSize = bounds.size; initialCenter = center }
        let delta = pan.translation(in: superview).applying(CGAffineTransform(rotationAngle: -(item.rotation ?? 0)))
        let size = CGSize(width: max(88, initialSize.width + delta.x), height: max(88, initialSize.height + delta.y))
        if pan.state == .changed {
            bounds.size = size
            let shift = CGPoint(x: (size.width - initialSize.width) / 2, y: (size.height - initialSize.height) / 2)
                .applying(CGAffineTransform(rotationAngle: item.rotation ?? 0))
            center = CGPoint(x: initialCenter.x + shift.x, y: initialCenter.y + shift.y)
        }
        if pan.state == .ended { resizeNote(to: CGSize(width: size.width / zoom, height: size.height / zoom)) }
        else if pan.state == .cancelled || pan.state == .failed { bounds.size = initialSize; center = initialCenter }
    }
    @objc private func tapped() {
        guard item.isLocked != true else { return }
        if selectsBeforeEditing { edit?(); return }
        if item.collapsed == true { item.collapsed = false; changed?(item) }
        else { beginInlineEditing() }
    }
    func beginInlineEditing() {
        guard item.isLocked != true, item.collapsed != true, textEditor == nil else { return }
            let editor = UITextView(frame: bounds)
            let text = NSMutableAttributedString(attributedString: RichTextDocument.attributed(item))
            text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
                if let font = value as? UIFont { text.addAttribute(.font, value: font.withSize(font.pointSize * zoom), range: range) }
            }
            editor.attributedText = text
            editor.backgroundColor = item.fillColorHex.flatMap(UIColor.init(presetHex:)) ?? UIColor(red: 1, green: 0.92, blue: 0.5, alpha: 1)
            editor.textContainerInset = UIEdgeInsets(top: 8 * zoom, left: 8 * zoom, bottom: 8 * zoom, right: 8 * zoom)
            editor.textContainer.lineFragmentPadding = 0
            editor.delegate = self
            editor.accessibilityLabel = "Sticky note text"
            let toolbar = UIToolbar(); toolbar.sizeToFit()
            toolbar.items = [UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil), UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(finishInlineEditing))]
            editor.inputAccessoryView = toolbar
            textEditor = editor; addSubview(editor)
            collapseButton.isHidden = true; resizeHandle.isHidden = true
            inlineEditingChanged?(true)
            editor.becomeFirstResponder()
    }
    func endInlineEditing() { finishInlineEditing() }
    @objc private func finishInlineEditing() {
        guard let editor = textEditor else { return }
        if editor.isFirstResponder { editor.resignFirstResponder() }
        else { textViewDidEndEditing(editor) }
    }
    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow == nil { finishInlineEditing() }
        super.willMove(toWindow: newWindow)
    }
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        textView.attributedText.length - range.length + (text as NSString).length <= 100_000
    }
    private func draft(from textView: UITextView) -> PageElement? {
        let text = NSMutableAttributedString(attributedString: textView.attributedText)
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let font = value as? UIFont { text.addAttribute(.font, value: font.withSize(min(96, max(8, font.pointSize / max(zoom, 0.01)))), range: range) }
        }
        guard let data = try? RichTextDocument.encode(text) else { return nil }
        var updated = item
        updated.richTextRTF = data; updated.text = text.string
        return updated
    }
    func textViewDidChange(_ textView: UITextView) {
        guard item.isLocked != true, let updated = draft(from: textView) else { return }
        draftChanged?(updated)
    }
    func textViewDidEndEditing(_ textView: UITextView) {
        guard textEditor === textView else { return }
        textEditor = nil
        inlineEditingChanged?(false)
        textView.removeFromSuperview()
        collapseButton.isHidden = item.isLocked == true || item.collapsed == true; resizeHandle.isHidden = item.collapsed == true || item.isLocked == true
        guard item.isLocked != true, let updated = draft(from: textView), updated != item else { return }
        item = updated
        draftChanged?(updated)
        changed?(item)
    }
    @objc private func drag(_ pan: UIPanGestureRecognizer) {
        guard item.isLocked != true, textEditor == nil else { return }
        let delta = pan.translation(in: superview)
        if pan.state == .changed { transform = CGAffineTransform(rotationAngle: item.rotation ?? 0).concatenating(CGAffineTransform(translationX: delta.x, y: delta.y)) }
        if pan.state == .ended {
            item.x = min(max(0, item.x + delta.x / zoom), max(0, pageSize.width - item.width))
            item.y = min(max(0, item.y + delta.y / zoom), max(0, pageSize.height - item.height))
            transform = CGAffineTransform(rotationAngle: item.rotation ?? 0); changed?(item)
        } else if pan.state == .cancelled { transform = CGAffineTransform(rotationAngle: item.rotation ?? 0) }
    }
}
