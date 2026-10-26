// Derived from Signotes, copyright (c) 2026 Diego Signorastri. MIT; see docs/Signotes-LICENSE.
import Foundation

struct DrawingToolPreset: Identifiable, Codable, Equatable, Sendable {
    static let minimumWidth = 0.5
    static let maximumWidth = 32.0

    let id: UUID
    var name: String
    var kind: DrawingToolKind
    var colorHex: String
    var width: Double

    init(
        id: UUID = UUID(),
        name: String,
        kind: DrawingToolKind,
        colorHex: String = "#000000",
        width: Double = 2.4
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.colorHex = colorHex
        self.width = min(max(width, Self.minimumWidth), Self.maximumWidth)
    }
}

extension DrawingToolPreset {
    static let defaultFountainPenID = UUID(uuidString: "F8320957-0D3E-4DF8-A01B-93B069B4E2C9")!
    static let defaultPenID = UUID(uuidString: "93E93495-D7FB-4E5F-9CB0-BE11CCCF6E64")!
    static let defaultPencilID = UUID(uuidString: "6AA1B4DF-E31B-4C46-AC37-1534A29CB2ED")!
    static let defaultMarkerID = UUID(uuidString: "A65047C3-9C0B-423D-B9C5-E5FBF8B76AA5")!
    static let defaultEraserID = UUID(uuidString: "2C6E7FE8-FC0E-4445-BE7D-8E55651647AA")!
    static let defaultLassoID = UUID(uuidString: "0C2817F4-036D-4B57-B02D-A3D551632A28")!

    static let builtInIDs: Set<UUID> = [
        defaultFountainPenID,
        defaultPenID,
        defaultPencilID,
        defaultMarkerID,
        defaultEraserID,
        defaultLassoID
    ]

    static let defaultFountainPen = DrawingToolPreset(
        id: defaultFountainPenID,
        name: "Fountain Pen Medium",
        kind: .fountainPen,
        width: 2.4
    )

    var isBuiltIn: Bool {
        Self.builtInIDs.contains(id)
    }

    var isWritingTool: Bool {
        kind.isWritingTool
    }

    static let defaults: [DrawingToolPreset] = [
        defaultFountainPen,
        DrawingToolPreset(
            id: defaultPenID,
            name: "Pen",
            kind: .pen,
            width: 2.0
        ),
        DrawingToolPreset(
            id: defaultPencilID,
            name: "Pencil",
            kind: .pencil,
            colorHex: "#3A3A3A",
            width: 3.0
        ),
        DrawingToolPreset(
            id: defaultMarkerID,
            name: "Marker",
            kind: .marker,
            colorHex: "#FFE66D",
            width: 8.0
        ),
        DrawingToolPreset(
            id: defaultEraserID,
            name: "Eraser",
            kind: .eraser,
            width: 8.0
        ),
        DrawingToolPreset(
            id: defaultLassoID,
            name: "Lasso",
            kind: .lasso,
            width: 1.0
        )
    ]
}
