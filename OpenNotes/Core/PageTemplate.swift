// Derived from Signotes, copyright (c) 2026 Diego Signorastri. MIT; see docs/Signotes-LICENSE.
enum PageTemplate: String, Codable, CaseIterable, Identifiable, Equatable, Sendable {
    case blank
    case ruled
    case grid
    case dotted

    var id: String { rawValue }
    var title: String {
        switch self {
        case .blank: return "Blank"
        case .ruled: return "Ruled"
        case .grid: return "Grid"
        case .dotted: return "Dotted"
        }
    }
}

