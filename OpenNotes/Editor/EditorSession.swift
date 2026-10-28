import SwiftUI
import PencilKit
import Vision

@MainActor
final class EditorSession: ObservableObject {
    @Published var page: NotePage?
    var drawing = PKDrawing()
    @Published var searchHighlights: [CGRect] = []
    @Published var background: UIImage?
    @Published var dirty = false
    @Published var busy = false
    @Published var error: String?
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    let canvas = PKCanvasView()
    var canvasPageID: UUID?
    func refreshUndoAvailability() {
        let undo = canvas.undoManager
        let undoAvailable = undo?.canUndo == true, redoAvailable = undo?.canRedo == true
        if canUndo != undoAvailable { canUndo = undoAvailable }
        if canRedo != redoAvailable { canRedo = redoAvailable }
    }
    private let preferences: UserDefaults
    private var restoringTool = false
    private var instrumentPresets: [DrawingToolPreset] = []
    @Published var toolSettings = EditorToolSettings() {
        didSet { preferences.set(try? JSONEncoder().encode(toolSettings), forKey: "editorToolSettings") }
    }
    func setFavoriteColors(_ colors: [String]) {
        let key = selectedTool == .fountainPen ? "pen" : selectedTool.rawValue
        toolSettings.favoriteColors[key] = colors
    }
    @Published var selectedTool = DrawingToolKind.pen {
        didSet {
            guard oldValue != selectedTool else { return }
            Diagnostics.shared.record("tool.selected", ["kind": selectedTool.rawValue])
            preferences.set(selectedTool.rawValue, forKey: "inkTool")
            restoreInstrument()
        }
    }
    @Published var inkColor = Color.black { didSet { saveInstrument() } }
    @Published var inkWidth = 3.0 { didSet { saveInstrument() } }
    private func restoreInstrument() {
        guard let preset = instrumentPresets.first(where: { $0.kind == selectedTool }) else { return }
        restoringTool = true
        inkColor = Color(UIColor(presetHex: preset.colorHex) ?? .black)
        inkWidth = preset.width
        restoringTool = false
    }
    private func saveInstrument() {
        guard !restoringTool, inkWidth.isFinite, inkWidth > 0,
              let index = instrumentPresets.firstIndex(where: { $0.kind == selectedTool }) else { return }
        instrumentPresets[index].colorHex = UIColor(inkColor).presetHex
        instrumentPresets[index].width = min(DrawingToolPreset.maximumWidth, max(DrawingToolPreset.minimumWidth, inkWidth))
        preferences.set(try? JSONEncoder().encode(instrumentPresets), forKey: "instrumentPresets")
        preferences.set(inkWidth, forKey: "inkWidth")
        preferences.set(try? NSKeyedArchiver.archivedData(withRootObject: UIColor(inkColor), requiringSecureCoding: true), forKey: "inkColor")
    }
    var paperInkColor: UIColor {
        UIColor(presetHex: UIColor(inkColor).presetHex) ?? .black
    }
    func setInkColor(_ color: Color) {
        inkColor = Color(UIColor(presetHex: UIColor(color).presetHex) ?? .black)
    }
    var documentInkWidth: Double { (tool as? PKInkingTool).map { Double($0.width) } ?? inkWidth }
    var documentInkWidthRange: ClosedRange<Double> {
        let type = inkingType
        let factor = selectedTool == .marker ? 4.0 : 1.0
        let minimum = max(DrawingToolPreset.minimumWidth * factor, Double(type.validWidthRange.lowerBound))
        let maximum = min(DrawingToolPreset.maximumWidth * factor, Double(type.validWidthRange.upperBound))
        return minimum...maximum
    }
    func setDocumentInkWidth(_ width: Double) {
        guard width.isFinite else { return }
        let range = documentInkWidthRange
        inkWidth = min(range.upperBound, max(range.lowerBound, width)) / (selectedTool == .marker ? 4 : 1)
    }
    // Use native ink types so the live stroke and the saved stroke remain identical.
    var inkingType: PKInk.InkType {
        if selectedTool == .pencil { return .pencil }
        if #available(iOS 17.0, *) {
            if selectedTool == .marker { return toolSettings.markerTiltEnabled == false ? .monoline : .marker }
            if !toolSettings.penPressureEnabled { return .monoline }
            return toolSettings.penStyle == .fountain || selectedTool == .fountainPen ? .fountainPen : .pen
        }
        return selectedTool == .marker ? .marker : .pen
    }
    var tool: PKTool {
        switch selectedTool {
        case .eraser:
            let type: PKEraserTool.EraserType = toolSettings.eraserMode == .pixel ? .bitmap : .vector
            if #available(iOS 16.4, *) { return PKEraserTool(type, width: toolSettings.eraserWidth) }
            return PKEraserTool(type)
        case .lasso: return PKLassoTool()
        default:
            let roundHighlighter = selectedTool == .marker && toolSettings.markerTiltEnabled == false
            let color = roundHighlighter ? paperInkColor.withAlphaComponent(0.3) : paperInkColor
            return PKInkingTool(inkingType, color: color, width: inkWidth * (selectedTool == .marker ? 4 : 1))
        }
    }
    let store: LibraryStore
    let noteID: UUID
    var artwork: PageArtwork?
    var backgroundData: Data?
    var resources: [String: Data] = [:]
    private var opening = UUID()
    private var pending: [UUID: (NotePage, PKDrawing, UUID)] = [:]
    private var autosave: Task<Void, Never>?
    private var writeTask: Task<Bool, Never>?
    var ocrTask: Task<Void, Never>?
    init(store: LibraryStore, noteID: UUID, preferences: UserDefaults = .standard) {
        self.store = store; self.noteID = noteID; self.preferences = preferences
        if let data = preferences.data(forKey: "editorToolSettings"),
           let saved = try? JSONDecoder().decode(EditorToolSettings.self, from: data),
           saved.stabilization.isFinite, (0...100).contains(saved.stabilization),
           saved.stabilizationByStyle?.values.allSatisfy({ $0.isFinite && (0...100).contains($0) }) != false,
           saved.pressureSensitivity.map({ $0.isFinite && (0...1).contains($0) }) != false,
           saved.eraserWidth.isFinite, (4...100).contains(saved.eraserWidth),
           Set(saved.toolbarOrder) == Set(EditorToolSettings.ToolbarItem.allCases),
           saved.toolbarOrder.count == EditorToolSettings.ToolbarItem.allCases.count,
           saved.favoriteColors.values.allSatisfy({ $0.count <= 64 && $0.allSatisfy { UIColor(presetHex: $0) != nil } }) {
            toolSettings = saved
        } else if let legacy = preferences.string(forKey: "favoriteInkColors") {
            let colors = legacy.split(separator: ",").map(String.init).filter { UIColor(presetHex: $0) != nil }
            if !colors.isEmpty { toolSettings.favoriteColors["pen"] = Array(colors.prefix(64)) }
        }
        let saved = preferences.data(forKey: "instrumentPresets").flatMap { try? JSONDecoder().decode([DrawingToolPreset].self, from: $0) } ?? []
        let legacyWidth = preferences.object(forKey: "inkWidth") as? Double
        let legacyColor = UIColor(data: preferences.data(forKey: "inkColor"))
        instrumentPresets = DrawingToolPreset.defaults.map { original in
            if var preset = saved.first(where: { $0.kind == original.kind }), preset.width.isFinite,
               (DrawingToolPreset.minimumWidth...DrawingToolPreset.maximumWidth).contains(preset.width), UIColor(presetHex: preset.colorHex) != nil {
                if preferences.integer(forKey: "instrumentPresetUnits") != 1 && preset.kind == .marker { preset.width /= 4 }
                return preset
            }
            var preset = original
            if preset.kind == .marker { preset.width /= 4 }
            if saved.isEmpty, original.isWritingTool {
                if let legacyWidth, legacyWidth.isFinite, legacyWidth > 0 { preset.width = min(32, max(0.5, legacyWidth)) }
                if let legacyColor { preset.colorHex = legacyColor.presetHex }
            }
            return preset
        }
        preferences.set(try? JSONEncoder().encode(instrumentPresets), forKey: "instrumentPresets")
        preferences.set(1, forKey: "instrumentPresetUnits")
        selectedTool = DrawingToolKind(rawValue: preferences.string(forKey: "inkTool") ?? "pen") ?? .pen
        restoreInstrument()
        canvas.tool = tool
    }
    private var prepared: (NotePage, Task<PreparedPage, Error>)?
    func preparePage(_ id: UUID?) {
        guard let id, let target = store.library.page(id: id), target.noteID == noteID else { cancelPreparation(); return }
        guard prepared?.0 != target else { return }
        cancelPreparation()
        let disk = store.disk
        prepared = (target, Task { try await PreparedPage.load(target, disk: disk) })
    }
    func cancelPreparation() { prepared?.1.cancel(); prepared = nil }
    func open(_ id: UUID? = nil) async {
        let request = UUID(); opening = request
        let started = ProcessInfo.processInfo.systemUptime
        Diagnostics.shared.record("page.open.begin", ["request": request.uuidString, "note": noteID.uuidString, "page": id?.uuidString ?? "first"])
        defer { Diagnostics.shared.record("page.open.end", ["request": request.uuidString, "currentPage": page?.id.uuidString ?? "none", "obsolete": String(opening != request), "ms": String(Int((ProcessInfo.processInfo.systemUptime - started) * 1000))]) }
        busy = true; defer { if opening == request { busy = false } }
        guard await flush(), opening == request else {
            if opening == request { cancelPreparation() }
            return
        }
        guard let target = id.flatMap({ store.library.page(id: $0) }).flatMap({ $0.noteID == noteID ? $0 : nil }) ?? store.library.firstPage(in: noteID) else { return }
        do {
            let reusable = page?.id == target.id && page?.backgroundID == target.backgroundID && page?.pdfIndex == target.pdfIndex ? artwork : nil
            let loaded: PreparedPage
            if let cached = prepared, cached.0 == target {
                prepared = nil
                do { loaded = try await cached.1.value }
                catch {
                    try Task.checkCancellation()
                    loaded = try await PreparedPage.load(target, disk: store.disk, reusing: reusable)
                }
            } else {
                cancelPreparation()
                loaded = try await PreparedPage.load(target, disk: store.disk, reusing: reusable)
            }
            guard opening == request, !Task.isCancelled else { return }
            // Flush strokes made while the old page was still visible.
            guard await flush(), opening == request else { return }
            backgroundData = loaded.background
            self.resources = page?.id == target.id ? self.resources.merging(loaded.resources) { _, new in new } : loaded.resources
            self.artwork = loaded.artwork
            if page?.id != target.id { searchHighlights = [] }
            drawing = page?.id == target.id ? drawing : loaded.drawing; page = store.library.page(id: target.id) ?? target
            error = nil
            UserDefaults.standard.set(noteID.uuidString, forKey: "lastNote")
            UserDefaults.standard.set(target.id.uuidString, forKey: "lastPage-\(noteID)")
        } catch { Diagnostics.shared.failure("page.open.failure", error: error); if opening == request { self.error = error.localizedDescription } }
    }
    func changed(_ drawing: PKDrawing) {
        guard let page else { return }
        self.drawing = drawing
        if !dirty { dirty = true; Diagnostics.shared.record("ink.dirty", ["page": page.id.uuidString, "strokes": String(drawing.strokes.count)]) }
        pending[page.id] = (page, drawing, UUID())
        autosave?.cancel()
        autosave = Task {
            do { try await Task.sleep(nanoseconds: 700_000_000) } catch { return }
            _ = await flush()
        }
    }
    @discardableResult func flush() async -> Bool {
        autosave?.cancel(); autosave = nil
        if let writeTask { _ = await writeTask.value; return await flush() }
        if pending.isEmpty {
            if dirty { store.persist() }
            let saved = await store.flush()
            if saved { dirty = false }
            return saved
        }
        let batch = pending
        Diagnostics.shared.record("ink.save.begin", ["pages": String(batch.count)])
        let task = Task { () -> Bool in
            defer { writeTask = nil }
            do {
                for (id, item) in batch {
                    let (page, drawing, revision) = item
                    let data = await Task.detached(priority: .utility) { drawing.dataRepresentation() }.value
                    try await store.disk.write(data, name: page.drawingResourceID)
                    if pending[id]?.2 == revision { pending[id] = nil }
                    if var latest = store.library.page(id: id) {
                        latest.drawingRevision = (latest.drawingRevision ?? 0) + 1
                        store.updatePage(latest)
                        if self.page?.id == id { self.page = store.library.page(id: id) }
                    }
                }
                guard await store.flush() else { throw CocoaError(.fileWriteUnknown) }
                dirty = !pending.isEmpty; Diagnostics.shared.record("ink.save.ok", ["remaining": String(pending.count)]); return true
            } catch { Diagnostics.shared.failure("editor.failure", error: error); self.error = "Unsaved handwriting: \(error.localizedDescription)"; return false }
        }
        writeTask = task
        return await task.value
    }
    func refresh(_ updated: NotePage) async {
        guard await flush() else { return }
        var updated = updated
        if let latest = store.library.page(id: updated.id) {
            updated.drawingRevision = latest.drawingRevision
            updated.pdfText = latest.pdfText ?? updated.pdfText
            updated.ocrText = latest.ocrText
        }
        store.updatePage(updated)
        await open(updated.id)
    }
    @discardableResult func apply(_ action: DocumentAction) async -> Bool {
        guard action.pageID == page?.id, await flush() else { return false }
        let previousDrawing = drawing, previousElements = page?.elements ?? []
        do {
            try await store.apply(action)
            guard await store.flush() else { self.error = store.error; return false }
            error = nil
            await open(action.pageID)
            if error == nil, action.kind != .setBookmark {
                registerContentUndo(previousDrawing, elements: previousElements, actionName: "Edit elements")
            }
            return page?.id == action.pageID && error == nil
        } catch { Diagnostics.shared.failure("editor.failure", error: error); self.error = error.localizedDescription; return false }
    }
    func replaceContent(_ drawing: PKDrawing, elements: [PageElement], actionName: String) {
        guard let page else { return }
        do {
            let updated = try DocumentAction(pageID: page.id, kind: .setElements, elements: elements).applying(to: page)
            guard elements.allSatisfy({ $0.kind != .image || $0.resource.flatMap { resources[$0] } != nil }) else { throw CocoaError(.fileNoSuchFile) }
            let previousDrawing = self.drawing, previousElements = page.elements ?? []
            registerContentUndo(previousDrawing, elements: previousElements, actionName: actionName)
            store.updatePage(updated)
            self.page = store.library.page(id: page.id) ?? updated
            artwork = PageArtwork(page: updated, data: backgroundData, resources: resources)
            canvas.drawing = drawing
            changed(drawing)
            refreshUndoAvailability()
        } catch { self.error = error.localizedDescription }
    }
    private func registerContentUndo(_ drawing: PKDrawing, elements: [PageElement], actionName: String) {
        canvas.undoManager?.registerUndo(withTarget: self) { target in
            target.replaceContent(drawing, elements: elements, actionName: actionName)
        }
        canvas.undoManager?.setActionName(actionName)
    }
    func insertImage(_ image: UIImage, at position: CGPoint? = nil) async {
        guard await flush(), let original = page else { return }
        do {
            let (data, size) = try await Task.detached(priority: .userInitiated) { try ImportedImage.encode(image, crop: nil) }.value
            guard page?.id == original.id else { throw CocoaError(.userCancelled) }
            var item = PageElement(kind: .image)
            let pageSize = PageRenderer.size(original)
            item.width = min(pageSize.width * 0.6, 420)
            item.height = item.width * size.height / max(1, size.width)
            if item.height > pageSize.height * 0.6 { item.width *= pageSize.height * 0.6 / item.height; item.height = pageSize.height * 0.6 }
            item.x = min(max(0, position?.x ?? (pageSize.width - item.width) / 2), pageSize.width - item.width)
            item.y = min(max(0, position?.y ?? (pageSize.height - item.height) / 2), pageSize.height - item.height)
            let name = UUID().uuidString + ".png"
            try await store.disk.write(data, name: name); item.resource = name
            await apply(.init(pageID: original.id, kind: .upsertElement, element: item))
        } catch { Diagnostics.shared.failure("editor.failure", error: error); self.error = error.localizedDescription }
    }
    func paste(at point: CGPoint) async {
        guard await flush(), let page else { return }
        do {
            let size = PageRenderer.size(page)
            if let bytes = UIPasteboard.general.data(forPasteboardType: DocumentClipboard.inkType) {
                let pasted = try DocumentClipboard.decodeInk(bytes, at: point, pageSize: size)
                let previous = canvas.drawing
                let merged = PKDrawing(strokes: previous.strokes + pasted.strokes)
                canvas.undoManager?.registerUndo(withTarget: canvas) { canvas in canvas.drawing = previous }
                canvas.drawing = merged; changed(merged)
            } else if let image = UIPasteboard.general.image {
                await insertImage(image, at: point)
            } else if let text = UIPasteboard.general.string, !text.isEmpty {
                guard text.count <= 100_000 else { throw CocoaError(.fileReadTooLarge) }
                var item = PageElement(kind: .text)
                item.text = text
                item.width = min(300, size.width); item.height = min(180, size.height)
                item.x = min(max(0, point.x), size.width - item.width); item.y = min(max(0, point.y), size.height - item.height)
                await apply(.init(pageID: page.id, kind: .upsertElement, element: item))
            } else { error = "The clipboard contains no compatible image, text or strokes." }
        } catch { Diagnostics.shared.failure("editor.failure", error: error); self.error = error.localizedDescription }
    }
    func recognize() {
        guard let page, let image = background?.cgImage else { return }
        ocrTask?.cancel(); busy = true
        ocrTask = Task {
            do {
                let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
                let text = try await withTaskCancellationHandler(operation: {
                    try await Task.detached(priority: .utility) {
                        try VNImageRequestHandler(cgImage: image).perform([request])
                        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                    }.value
                }, onCancel: { request.cancel() })
                try Task.checkCancellation()
                guard var updated = store.library.page(id: page.id) else { return }
                updated.recognizedText = text
                store.updatePage(updated)
                if self.page?.id == page.id { self.page = updated }
            } catch is CancellationError { }
            catch { Diagnostics.shared.failure("editor.failure", error: error); self.error = error.localizedDescription }
            busy = false
        }
    }
    func cancelOCR() { ocrTask?.cancel(); ocrTask = nil; busy = false }
}

private extension UIColor {
    convenience init?(data: Data?) {
        guard let data, let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: data) else { return nil }
        self.init(cgColor: color.cgColor)
    }
}
