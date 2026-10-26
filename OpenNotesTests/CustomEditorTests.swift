import XCTest
import SwiftUI
import PencilKit
@testable import OpenNotes

@MainActor
final class CustomEditorTests: XCTestCase {
    func testDoubleTapFitsWidthFromAnyManualZoomThenFitsHeight() {
        for (viewport, page) in [(CGSize(width: 800, height: 500), CGSize(width: 794, height: 1123)),
                                 (CGSize(width: 600, height: 900), CGSize(width: 1000, height: 500))] {
            let view = PageScrollView(canvas: PKCanvasView())
            view.frame = CGRect(origin: .zero, size: viewport); view.pageSize = page; view.layoutIfNeeded()
            view.canvas.setZoomScale(2.7, animated: false)
            let point = CGPoint(x: viewport.width * 0.4, y: viewport.height * 0.6)
            view.toggleFit(at: point)
            XCTAssertEqual(view.canvas.zoomScale, view.widthFitZoom, accuracy: 0.001)
            view.toggleFit(at: point)
            XCTAssertEqual(view.canvas.zoomScale, view.heightFitZoom, accuracy: 0.001)
            XCTAssertEqual(view.canvas.contentOffset.y, -view.canvas.contentInset.top, accuracy: 0.001)
            view.toggleFit(at: point)
            XCTAssertEqual(view.canvas.zoomScale, view.widthFitZoom, accuracy: 0.001)
            XCTAssertEqual(view.canvas.contentOffset.x, -view.canvas.contentInset.left, accuracy: 0.001)
        }
    }
    func testHeightFitAboveNaturalSizeStillAllowsPagingOnLargeIPad() {
        let view = PageScrollView(canvas: PKCanvasView())
        view.frame = CGRect(x: 0, y: 0, width: 1032, height: 1200)
        view.pageSize = CGSize(width: 794, height: 1123); view.layoutIfNeeded()
        XCTAssertGreaterThan(view.canvas.minimumZoomScale, 1)
        view.fitAxis(horizontal: true)
        view.toggleFit(at: CGPoint(x: 516, y: 600))
        XCTAssertEqual(view.canvas.zoomScale, view.canvas.minimumZoomScale, accuracy: 0.001)
        XCTAssertTrue(view.pageTurn.shouldBegin(velocity: CGPoint(x: -250, y: 0)))
    }
    func testPaperColorAndExportRemainIdenticalAcrossInterfaceStyles() throws {
        XCTAssertEqual(UIColor.label.presetHex, "#000000")
        let color = try XCTUnwrap(UIColor(presetHex: "#315BB1"))
        let points = (0...20).map { index in
            PKStrokePoint(location: CGPoint(x: 20 + index * 8, y: 50), timeOffset: Double(index) / 20,
                          size: CGSize(width: 12, height: 12), opacity: 1, force: 1, azimuth: 0, altitude: 1)
        }
        let drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: color), path: PKStrokePath(controlPoints: points, creationDate: Date()))])
        var light: UIImage!, dark: UIImage!
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent { light = drawing.paperImage(from: rect, scale: 1) }
        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent { dark = drawing.paperImage(from: rect, scale: 1) }
        XCTAssertEqual(light.pngData(), dark.pngData())
        let source = try XCTUnwrap(dark.cgImage?.cropping(to: CGRect(x: 100, y: 50, width: 1, height: 1)))
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(source, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        for (actual, expected) in zip(pixel.prefix(3), [49, 91, 177]) { XCTAssertEqual(Int(actual), expected, accuracy: 2) }
        let view = PageScrollView(canvas: PKCanvasView())
        view.overrideUserInterfaceStyle = .dark
        XCTAssertEqual(view.canvas.traitCollection.userInterfaceStyle, .light)
    }
}
