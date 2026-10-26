// Derived from Signotes, copyright (c) 2026 Diego Signorastri. MIT; see docs/Signotes-LICENSE.
enum PageFormat: String, Codable, CaseIterable, Equatable, Sendable {
    case a4Portrait

    var width: Double {
        switch self {
        case .a4Portrait:
            return 210
        }
    }

    var height: Double {
        switch self {
        case .a4Portrait:
            return 297
        }
    }

    var aspectRatio: Double {
        width / height
    }
}

