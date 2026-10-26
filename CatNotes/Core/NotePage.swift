// Derived from Signotes, copyright (c) 2026 Diego Signorastri. MIT; see docs/Signotes-LICENSE.
import Foundation

struct NotePage: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var noteID: UUID
    var elements: [PageElement]?
    var backgroundID: String?
    var pdfIndex: Int?
    var width: Double?
    var height: Double?
    var text: String?
    var recognizedText: String?
    var pdfText: PageTextContent?
    var ocrText: PageTextContent?
    var drawingRevision: Int?
    var modifiedAt: Date?
    var revision: Int?
    var bookmark: Bool?
    var index: Int
    var format: PageFormat
    var template: PageTemplate
    var drawingResourceID: String

    init(
        id: UUID = UUID(),
        noteID: UUID,
        index: Int,
        format: PageFormat,
        template: PageTemplate,
        drawingResourceID: String
    ) {
        self.id = id
        self.noteID = noteID
        self.index = index
        self.format = format
        self.template = template
        self.drawingResourceID = drawingResourceID
    }
}

