import UIKit
import ImageIO

enum ImportedImage {
    static func decode(_ data: Data) throws -> UIImage {
        guard !data.isEmpty, data.count <= 150_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 3200] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        // shortcut: inserted photos are limited to 3200 pixels, retain originals when full-resolution image export is added.
        return UIImage(cgImage: image)
    }
    static func encode(_ source: UIImage, crop: CGRect?) throws -> (Data, CGSize) {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let pixels = CGSize(width: source.size.width * source.scale, height: source.size.height * source.scale)
        let scale = min(1, 3200 / max(1, pixels.width, pixels.height))
        let size = CGSize(width: pixels.width * scale, height: pixels.height * scale)
        var image = UIGraphicsImageRenderer(size: size, format: format).image { _ in source.draw(in: CGRect(origin: .zero, size: size)) }
        if let crop {
            guard crop.width > 0, crop.height > 0, CGRect(x: 0, y: 0, width: 1, height: 1).contains(crop), let cgImage = image.cgImage,
                  let cropped = cgImage.cropping(to: CGRect(x: Double(cgImage.width) * crop.minX, y: Double(cgImage.height) * crop.minY, width: Double(cgImage.width) * crop.width, height: Double(cgImage.height) * crop.height).integral) else { throw CocoaError(.fileReadCorruptFile) }
            image = UIImage(cgImage: cropped)
        }
        guard let data = image.pngData() else { throw CocoaError(.fileReadCorruptFile) }
        return (data, image.size)
    }
}
