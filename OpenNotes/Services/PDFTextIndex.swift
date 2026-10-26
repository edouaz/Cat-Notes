import PDFKit

// PDFKit objects stay inside the task that created them; only value data crosses actors.
enum PDFTextIndex {
    static func extract(_ data: Data) throws -> [PageTextContent] {
        guard let document = PDFDocument(data: data), !document.isLocked else { throw CocoaError(.fileReadCorruptFile) }
        return (0..<document.pageCount).map { index in
            guard let page = document.page(at: index) else {
                return PageTextContent(source: .pdf, status: .needsRecognition, text: "", blocks: [])
            }
            var size = page.bounds(for: .cropBox).size
            if abs(page.rotation) % 180 == 90 { size = CGSize(width: size.height, height: size.width) }
            let transform = page.pageRef?.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: size), rotate: 0, preserveAspectRatio: true) ?? .identity
            let text = page.string ?? ""
            let selection = page.selection(for: page.bounds(for: .cropBox))
            let blocks = (selection?.selectionsByLine() ?? []).compactMap { line -> PageTextContent.Block? in
                guard let text = line.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                let rect = line.bounds(for: page).applying(transform)
                guard !rect.isNull, rect.width.isFinite, rect.height.isFinite else { return nil }
                return .init(text: text, x: rect.minX, y: size.height - rect.maxY, width: rect.width, height: rect.height, confidence: nil)
            }
            return PageTextContent(source: .pdf, status: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .needsRecognition : .available, text: text, blocks: blocks, engine: "PDFKit")
        }
    }
}
