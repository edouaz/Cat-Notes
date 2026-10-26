import Foundation
import PencilKit
import UIKit

struct DocumentContext: Encodable {
    var formatVersion = 1
    var coordinates = "page points; origin top-left; x right; y down"
    var folderPath: [NotebookFolder]
    var note: NoteDocument
    var pages: [Page]
    struct Page: Encodable {
        var metadata: NotePage
        var searchableText: String
        var strokes: [Stroke]
    }
    struct Stroke: Encodable {
        var tool: String
        var rgba: [Double]
        var transform: [Double]
        var visiblePathRanges: [[Double]]?
        var points: [Point]
    }
    struct Point: Encodable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
        var force: Double
        var time: Double
        var opacity: Double
        var azimuth: Double
        var altitude: Double
    }
    init(archive: NotebookArchive, folderPath: [NotebookFolder] = []) throws {
        self.folderPath = folderPath
        note = archive.note
        pages = try archive.pages.map { page in
            guard let bytes = archive.resources[page.drawingResourceID] else { throw CocoaError(.fileNoSuchFile) }
            let drawing = try PKDrawing(data: bytes)
            return Page(metadata: page, searchableText: page.searchableText, strokes: drawing.strokes.map { stroke in
                var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 1
                stroke.ink.color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                let t = stroke.transform
                return Stroke(tool: stroke.ink.inkType.rawValue, rgba: [red, green, blue, alpha].map(Double.init), transform: [t.a, t.b, t.c, t.d, t.tx, t.ty].map(Double.init), visiblePathRanges: stroke.mask == nil ? nil : stroke.maskedPathRanges.map { [Double($0.lowerBound), Double($0.upperBound)] }, points: stroke.path.map { point in
                    let location = point.location.applying(stroke.transform)
                    return Point(x: location.x, y: location.y, width: point.size.width, height: point.size.height, force: point.force, time: point.timeOffset, opacity: point.opacity, azimuth: point.azimuth, altitude: point.altitude)
                })
            })
        }
    }
}
