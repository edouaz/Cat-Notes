import SwiftUI
import UIKit

enum RichTextDocument {
    static func decode(_ data: Data) throws -> NSAttributedString {
        guard data.count <= 2 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        let text = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        guard text.length <= 100_000 else { throw CocoaError(.fileReadTooLarge) }
        var valid = true
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, _, _ in
            if attributes[.attachment] != nil { valid = false }
            if let font = attributes[.font] as? UIFont, !font.pointSize.isFinite || !(8...96).contains(font.pointSize) { valid = false }
        }
        guard valid else { throw CocoaError(.fileReadCorruptFile) }
        return text
    }
    static func encode(_ text: NSAttributedString) throws -> Data {
        let data = try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        _ = try decode(data)
        return data
    }
    static func isValid(_ data: Data, text: String) -> Bool { (try? decode(data).string) == text }
    static func attributed(_ item: PageElement) -> NSAttributedString {
        if let data = item.richTextRTF, let value = try? decode(data) { return value }
        return NSAttributedString(string: item.text, attributes: [.font: UIFont.systemFont(ofSize: item.textFontSize ?? 16),
            .foregroundColor: item.textColorHex.flatMap(UIColor.init(presetHex:)) ?? UIColor.black])
    }
}

@MainActor
final class RichTextFormatting: ObservableObject {
    weak var view: UITextView?
    var changed: (() -> Void)?
    private func apply(in target: NSRange? = nil, _ change: (inout [NSAttributedString.Key: Any]) -> Void) {
        guard let view else { return }
        let selection = view.selectedRange
        let range = target ?? selection
        if range.length == 0 {
            var attributes = view.typingAttributes
            change(&attributes); view.typingAttributes = attributes
        } else {
            let text = NSMutableAttributedString(attributedString: view.attributedText)
            text.enumerateAttributes(in: range) { original, subrange, _ in
                var attributes = original; change(&attributes); text.setAttributes(attributes, range: subrange)
            }
            view.attributedText = text; view.selectedRange = selection
            changed?()
        }
    }
    func trait(_ trait: UIFontDescriptor.SymbolicTraits) {
        apply { attributes in
            let font = attributes[.font] as? UIFont ?? .systemFont(ofSize: 16)
            var traits = font.fontDescriptor.symbolicTraits
            if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
            if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) { attributes[.font] = UIFont(descriptor: descriptor, size: font.pointSize) }
        }
    }
    func toggle(_ key: NSAttributedString.Key) { apply { $0[key] = ($0[key] as? Int ?? 0) == 0 ? 1 : 0 } }
    func font(_ family: String? = nil, size: CGFloat? = nil) {
        apply { attributes in
            let font = attributes[.font] as? UIFont ?? .systemFont(ofSize: 16)
            let descriptor = family.map { font.fontDescriptor.withFamily($0) } ?? font.fontDescriptor
            attributes[.font] = UIFont(descriptor: descriptor, size: size ?? font.pointSize)
        }
    }
    func color(_ color: UIColor) { apply { $0[.foregroundColor] = color } }
    func align(_ alignment: NSTextAlignment) {
        guard let view else { return }
        let range = (view.text as NSString).paragraphRange(for: view.selectedRange)
        apply(in: range) { attributes in
            let style = (attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            style.alignment = alignment; attributes[.paragraphStyle] = style
        }
    }
    func list(numbered: Bool) {
        guard let view else { return }
        let text = view.text as NSString
        let range = text.paragraphRange(for: view.selectedRange)
        let original = view.attributedText.attributedSubstring(from: range)
        let result = NSMutableAttributedString(string: "")
        var start = 0
        for (index, line) in original.string.components(separatedBy: "\n").enumerated() {
            let count = (line as NSString).length
            let attributes = original.length > start ? original.attributes(at: start, effectiveRange: nil) : view.typingAttributes
            result.append(NSAttributedString(string: numbered ? "\(index + 1). " : "• ", attributes: attributes))
            result.append(original.attributedSubstring(from: NSRange(location: start, length: count)))
            start += count
            if start < original.length { result.append(original.attributedSubstring(from: NSRange(location: start, length: 1))); start += 1 }
        }
        let updated = NSMutableAttributedString(attributedString: view.attributedText)
        updated.replaceCharacters(in: range, with: result)
        view.attributedText = updated
        view.selectedRange = NSRange(location: range.location, length: result.length)
        changed?()
    }
}

struct StickyRichTextEditor: UIViewRepresentable {
    @Binding var item: PageElement
    let formatting: RichTextFormatting
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.allowsEditingTextAttributes = true
        view.attributedText = RichTextDocument.attributed(item)
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        view.accessibilityLabel = "Sticky note text"
        formatting.view = view
        formatting.changed = { [weak coordinator = context.coordinator, weak view] in if let view { coordinator?.textViewDidChange(view) } }
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) { context.coordinator.owner = self }
    final class Coordinator: NSObject, UITextViewDelegate {
        var owner: StickyRichTextEditor
        init(_ owner: StickyRichTextEditor) { self.owner = owner }
        func textViewDidChange(_ textView: UITextView) {
            guard let data = try? RichTextDocument.encode(textView.attributedText) else { return }
            owner.item.text = textView.text
            owner.item.richTextRTF = data
        }
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            textView.attributedText.length - range.length + (text as NSString).length <= 100_000
        }
    }
}
