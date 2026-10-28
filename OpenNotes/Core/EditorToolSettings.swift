import Foundation

struct EditorToolSettings: Codable, Equatable {
    enum PenStyle: String, Codable, CaseIterable { case ballpoint, fountain, brush }
    enum EraserMode: String, Codable, CaseIterable { case stroke, pixel, intelligent }
    enum LassoShape: String, Codable, CaseIterable { case freeform, rectangle }
    enum ToolbarItem: String, Codable, CaseIterable, Identifiable {
        case pen, pencil, marker, eraser, lasso, image, stickyNote
        var id: Self { self }
        var title: String {
            switch self {
            case .pen: return "Pen"
            case .pencil: return "Pencil"
            case .marker: return "Highlighter"
            case .eraser: return "Eraser"
            case .lasso: return "Lasso"
            case .image: return "Image"
            case .stickyNote: return "Sticky note"
            }
        }
        var symbol: String {
            switch self {
            case .pen: return "pencil.tip"
            case .pencil: return "pencil"
            case .marker: return "highlighter"
            case .eraser: return "eraser"
            case .lasso: return "lasso"
            case .image: return "photo"
            case .stickyNote: return "note.text"
            }
        }
        var drawingTool: DrawingToolKind? { DrawingToolKind(rawValue: rawValue) }
    }

    var penStyle = PenStyle.ballpoint
    var stabilization = 0.0
    // Optional additions preserve decoding of settings saved before the Goodnotes adaptation.
    var stabilizationByStyle: [String: Double]?
    var pressureSensitivity: Double?
    var pressureEnabled: Bool?
    var tiltEnabled: Bool?
    var rulerEnabled: Bool?
    var markerTiltEnabled: Bool?
    var penPressureEnabled: Bool { pressureEnabled ?? (penStyle != .ballpoint) }

    mutating func applyPenPreset(_ style: PenStyle) {
        penStyle = style
        pressureEnabled = style != .ballpoint
    }

    func stabilizationKey(for tool: DrawingToolKind) -> String {
        tool == .marker ? "marker" : penStyle.rawValue
    }
    func stabilization(for tool: DrawingToolKind) -> Double {
        stabilizationByStyle?[stabilizationKey(for: tool)] ?? stabilization
    }
    mutating func setStabilization(_ value: Double, for tool: DrawingToolKind) {
        if stabilizationByStyle == nil { stabilizationByStyle = [:] }
        let key = stabilizationKey(for: tool)
        stabilizationByStyle?[key] = value
    }
    var eraserMode = EraserMode.stroke
    var eraserWidth = 24.0
    var lassoShape = LassoShape.freeform
    var includeHandwriting = true
    var includeText: Bool?
    var includeImages = true
    var includeStickyNotes = true
    var shapeRecognitionEnabled = true
    var shapeAngleSnap: Bool?
    var toolbarOrder = ToolbarItem.allCases
    var hiddenTools: Set<ToolbarItem> = [.pencil]
    var favoriteColors: [String: [String]] = [:]

    func colors(for tool: DrawingToolKind) -> [String] {
        let key = tool == .fountainPen ? "pen" : tool.rawValue
        return favoriteColors[key] ?? (tool == .marker
            ? ["#FFE66D", "#A8E6CF", "#FFAFCC", "#A9D6FF", "#D9B8FF", "#FFC48C"]
            : ["#202725", "#1F665E", "#315BB1", "#B34242", "#9253A1", "#B77826"])
    }
}
