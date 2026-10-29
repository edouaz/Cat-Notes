import Foundation

struct PageElement: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable { case text, image, rectangle, ellipse, line, arrow, stickyNote, highlight }
    var id = UUID()
    var kind: Kind
    var x: Double = 60
    var y: Double = 120
    var width: Double = 220
    var height: Double = 120
    var text = "Text"
    var resource: String?
    var rotation: Double?
    var isLocked: Bool?
    var parentID: UUID?
    var zIndex: Double?
    var richTextRTF: Data?
    var collapsed: Bool?
    var textFontSize: Double?
    var textColorHex: String?
    var strokeWidth: Double?
    var strokeColorHex: String?
    var fillColorHex: String?
}
