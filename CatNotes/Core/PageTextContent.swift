import Foundation

struct PageTextContent: Codable, Equatable, Sendable {
    enum Source: String, Codable { case pdf, ocr }
    enum Status: String, Codable { case available, needsRecognition, needsReview }
    struct Block: Codable, Equatable, Sendable {
        var text: String
        // Page points, origin at the top left; never viewport/screen coordinates.
        var x: Double
        var y: Double
        var width: Double
        var height: Double
        var confidence: Double?
        var alternatives: [String]?
        var requiresReview: Bool?
    }
    var source: Source
    var status: Status
    var text: String
    var blocks: [Block]
    var engine: String?
    var drawingRevision: Int?
}

extension NotePage {
    var searchableText: String {
        ([pdfText?.text, text, ocrText == nil ? recognizedText : nil, ocrText?.drawingRevision == (drawingRevision ?? 0) ? ocrText?.text : nil] + (elements ?? []).filter { $0.kind == .text || $0.kind == .stickyNote }.map { Optional($0.text) })
            .compactMap { $0 }.joined(separator: "\n")
    }
}
