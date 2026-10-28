import UIKit
import PDFKit
import PencilKit

enum PageRenderer {
    static func size(_ page: NotePage) -> CGSize { CGSize(width: page.width ?? 794, height: page.height ?? 1123) }
    static func background(_ page: NotePage, data: Data?, resources: [String: Data] = [:], context: CGContext, pdfPage: CGPDFPage? = nil, images: [String: UIImage] = [:], pdfUnderlay: PKDrawing? = nil, inkScale: CGFloat = 2, inkRect: CGRect? = nil) {
        let bounds = CGRect(origin: .zero, size: size(page))
        UIColor.white.setFill(); context.fill(bounds)
        var drewPDF = false
        if let index = page.pdfIndex, let ref = pdfPage ?? data.flatMap({ PDFDocument(data: $0)?.page(at: index)?.pageRef }) {
            drewPDF = true
            let inkBounds = inkRect ?? bounds
            pdfUnderlay?.paperImage(from: inkBounds, scale: inkScale).draw(in: inkBounds)
            let highlights = (page.elements ?? []).filter { $0.kind == .highlight }
            for item in highlights {
                UIColor.systemYellow.withAlphaComponent(0.3).setFill()
                context.fill(CGRect(x: item.x, y: item.y, width: item.width, height: item.height))
            }
            context.saveGState()
            // Draw the original PDF last: white paper retains the ink; text stays opaque and sharp.
            if pdfUnderlay != nil || !highlights.isEmpty { context.setBlendMode(.multiply) }
            context.translateBy(x: 0, y: bounds.height); context.scaleBy(x: 1, y: -1)
            context.concatenate(ref.getDrawingTransform(.cropBox, rect: bounds, rotate: 0, preserveAspectRatio: true))
            context.drawPDFPage(ref); context.restoreGState()
        } else if let image = images["background"] ?? data.flatMap(UIImage.init(data:)) {
            image.draw(in: bounds)
        } else {
            PaperTemplateUIView.draw(page.template, in: context, rect: bounds)
        }
        elements(page, resources: resources, context: context, images: images, drewPDF: drewPDF)
    }
    static func elements(_ page: NotePage, resources: [String: Data], context: CGContext, images: [String: UIImage], drewPDF: Bool) {
        let bounds = CGRect(origin: .zero, size: size(page))
        for item in page.elements ?? [] {
            let rect = CGRect(x: item.x, y: item.y, width: item.width, height: item.height)
            (item.strokeColorHex.flatMap(UIColor.init(presetHex:)) ?? .black).setStroke()
            context.setLineWidth(item.strokeWidth.flatMap { $0.isFinite ? min(32, max(0.5, $0)) : nil } ?? 2)
            switch item.kind {
            case .image: if let name = item.resource { (images[name] ?? resources[name].flatMap(UIImage.init(data:)))?.draw(in: rect) }
            case .highlight:
                if !drewPDF { UIColor.systemYellow.withAlphaComponent(0.3).setFill(); context.fill(rect) }
            case .stickyNote:
                let noteRect = item.collapsed == true ? CGRect(x: item.x, y: item.y, width: 44, height: 44) : rect
                UIColor(red: 1, green: 0.92, blue: 0.5, alpha: 1).setFill(); context.fill(noteRect)
                if item.collapsed == true {
                    UIImage(systemName: "arrow.up.left.and.arrow.down.right")?.withTintColor(.darkGray, renderingMode: .alwaysOriginal).draw(in: noteRect.insetBy(dx: 12, dy: 12))
                } else {
                    (item.text as NSString).draw(in: noteRect.insetBy(dx: 8, dy: 8), withAttributes: [.font: UIFont.systemFont(ofSize: 16), .foregroundColor: UIColor.black])
                }
            case .text:
                let fontSize = item.textFontSize.flatMap { $0.isFinite ? min(96, max(8, $0)) : nil } ?? 20
                (item.text as NSString).draw(in: rect, withAttributes: [.font: UIFont.systemFont(ofSize: fontSize),
                    .foregroundColor: item.textColorHex.flatMap(UIColor.init(presetHex:)) ?? UIColor.black])
            case .rectangle, .ellipse:
                let shape = item.kind == .ellipse ? CGPath(ellipseIn: rect, transform: nil) : CGPath(rect: rect, transform: nil)
                if let color = item.fillColorHex.flatMap(UIColor.init(presetHex:)) {
                    color.setFill(); context.addPath(shape); context.fillPath()
                }
                context.addPath(shape); context.strokePath()
            case .line, .arrow:
                context.move(to: rect.origin); context.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); context.strokePath()
                if item.kind == .arrow {
                    let angle = atan2(rect.height, rect.width)
                    for offset in [-0.5, 0.5] {
                        context.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
                        context.addLine(to: CGPoint(x: rect.maxX - 20 * cos(angle + offset), y: rect.maxY - 20 * sin(angle + offset)))
                    }
                    context.strokePath()
                }
            }
        }
        if let text = page.text, !text.isEmpty {
            (text as NSString).draw(in: bounds.insetBy(dx: 32, dy: 32), withAttributes: [
                .font: UIFont.systemFont(ofSize: 20), .foregroundColor: UIColor.black
            ])
        }
    }
    static func composite(_ page: NotePage, data: Data?, drawing: PKDrawing?, resources: [String: Data] = [:], context: CGContext, pdfPage: CGPDFPage? = nil, images: [String: UIImage] = [:], inkScale: CGFloat = 2, inkRect: CGRect? = nil) {
        let reference = pdfPage ?? page.pdfIndex.flatMap { index in data.flatMap { PDFDocument(data: $0)?.page(at: index)?.pageRef } }
        let markers = reference == nil ? [] : drawing?.strokes.filter { $0.ink.inkType == .marker } ?? []
        background(page, data: data, resources: resources, context: context, pdfPage: reference, images: images,
                   pdfUnderlay: markers.isEmpty ? nil : PKDrawing(strokes: markers), inkScale: inkScale, inkRect: inkRect)
        let foreground = markers.isEmpty ? drawing : drawing.map { PKDrawing(strokes: $0.strokes.filter { $0.ink.inkType != .marker }) }
        let inkBounds = inkRect ?? CGRect(origin: .zero, size: size(page))
        foreground?.paperImage(from: inkBounds, scale: inkScale).draw(in: inkBounds)
    }
    static func image(_ page: NotePage, data: Data?, drawing: PKDrawing? = nil, resources: [String: Data] = [:], scale: CGFloat = 1) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = scale; format.opaque = true
        let bounds = CGRect(origin: .zero, size: size(page))
        return UIGraphicsImageRenderer(size: bounds.size, format: format).image { renderer in
            composite(page, data: data, drawing: drawing, resources: resources, context: renderer.cgContext, inkScale: scale)
        }
    }
    static func capture(_ page: NotePage, data: Data?, drawing: PKDrawing, resources: [String: Data], rect: CGRect, path: UIBezierPath? = nil) throws -> UIImage {
        let crop = rect.standardized.intersection(CGRect(origin: .zero, size: size(page)))
        guard !crop.isNull, crop.width >= 1, crop.height >= 1 else { throw CocoaError(.fileReadCorruptFile) }
        let scale = min(2, 2048 / max(crop.width, crop.height))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = path == nil
        return UIGraphicsImageRenderer(size: CGSize(width: ceil(crop.width * scale), height: ceil(crop.height * scale)), format: format).image { renderer in
            let context = renderer.cgContext
            context.scaleBy(x: scale, y: scale); context.translateBy(x: -crop.minX, y: -crop.minY)
            if let path { context.addPath(path.cgPath); context.clip() }
            composite(page, data: data, drawing: drawing, resources: resources, context: context, inkScale: scale, inkRect: crop)
        }
    }
    static func export(_ archive: NotebookArchive, indices: ClosedRange<Int>, output: URL) throws {
        try archive.validate()
        guard indices.lowerBound >= 0, indices.upperBound < archive.pages.count else { throw CocoaError(.validationMissingMandatoryProperty) }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 794, height: 1123))
        try renderer.writePDF(to: output) { renderer in
            for index in indices {
                let page = archive.pages[index]
                let bounds = CGRect(origin: .zero, size: size(page))
                renderer.beginPage(withBounds: bounds, pageInfo: [:])
                let drawing = archive.resources[page.drawingResourceID].flatMap { try? PKDrawing(data: $0) }
                composite(page, data: page.backgroundID.flatMap { archive.resources[$0] }, drawing: drawing, resources: archive.resources, context: renderer.cgContext)
            }
        }
    }
}
