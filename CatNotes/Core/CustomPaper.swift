import Foundation

struct CustomPaper: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var template: PageTemplate
    var resource: String?
    var pdfIndex: Int?
    var width: Double?
    var height: Double?
}
