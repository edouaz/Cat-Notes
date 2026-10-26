import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Rebuild platform-sized exports without redrawing or masking the source mascot.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let sourceURL = root.appendingPathComponent("docs/assets/mascot-source.png")
let catalog = root.appendingPathComponent("OpenNotes/Resources/Assets.xcassets")
let iconSet = catalog.appendingPathComponent("AppIcon.appiconset")
let web = root.appendingPathComponent("docs/assets")
try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let mascot = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
    fatalError("Expected a readable mascot-source.png")
}

func write(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Cannot write \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination), "PNG write failed")
}

func render(size: Int, background: [CGFloat]?, grayscale: Bool = false) -> CGImage {
    let alpha = background == nil ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: size * 4, space: colorSpace, bitmapInfo: alpha.rawValue) else {
        fatalError("Cannot allocate icon bitmap")
    }
    let rectangle = CGRect(x: 0, y: 0, width: size, height: size)
    if let background {
        context.setFillColor(red: background[0], green: background[1], blue: background[2], alpha: 1)
        context.fill(rectangle)
    }
    context.interpolationQuality = .high
    context.draw(mascot, in: rectangle)
    if grayscale {
        let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
        for offset in stride(from: 0, to: size * size * 4, by: 4) {
            let value = UInt8((0.2126 * Double(pixels[offset]) + 0.7152 * Double(pixels[offset + 1]) + 0.0722 * Double(pixels[offset + 2])).rounded())
            pixels[offset] = value
            pixels[offset + 1] = value
            pixels[offset + 2] = value
        }
    }
    guard let image = context.makeImage() else { fatalError("Cannot finish icon bitmap") }
    precondition(image.width == size && image.height == size)
    return image
}

let variants: [(String, [CGFloat], Bool)] = [
    ("light", [0.929, 0.957, 1.0], false),
    ("dark", [0.051, 0.086, 0.145], false),
    ("tinted", [0.051, 0.086, 0.145], true)
]
var images: [[String: Any]] = []
for (name, background, grayscale) in variants {
    let filename = "AppIcon-\(name).png"
    write(render(size: 1024, background: background, grayscale: grayscale), to: iconSet.appendingPathComponent(filename))
    write(render(size: 256, background: background, grayscale: grayscale), to: web.appendingPathComponent("icon-\(name).png"))
    var image: [String: Any] = ["filename": filename, "idiom": "universal", "platform": "ios", "size": "1024x1024"]
    if name != "light" {
        image["appearances"] = [["appearance": "luminosity", "value": name == "dark" ? "dark" : "tinted"]]
    }
    images.append(image)
}
write(render(size: 512, background: nil), to: web.appendingPathComponent("mascot.png"))
let info: [String: Any] = ["author": "xcode", "version": 1]
try JSONSerialization.data(withJSONObject: ["images": images, "info": info], options: [.prettyPrinted, .sortedKeys]).write(to: iconSet.appendingPathComponent("Contents.json"))
try JSONSerialization.data(withJSONObject: ["info": info], options: [.prettyPrinted, .sortedKeys]).write(to: catalog.appendingPathComponent("Contents.json"))
print("Generated native app icon catalog and website exports.")
