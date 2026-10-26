// Derived from Signotes, copyright (c) 2026 Diego Signorastri. MIT; see docs/Signotes-LICENSE.
enum DrawingToolKind: String, Codable, CaseIterable, Identifiable, Equatable, Hashable, Sendable {
    case fountainPen
    case pen
    case pencil
    case marker
    case eraser
    case lasso

    var id: String { rawValue }

    var isWritingTool: Bool {
        switch self {
        case .fountainPen, .pen, .pencil, .marker:
            true
        case .eraser, .lasso:
            false
        }
    }
}
