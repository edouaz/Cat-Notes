import Testing
import XCTest
import PencilKit
@testable import OpenNotes

@MainActor
final class InkPipelineTests: XCTestCase {
    private func stroke(transform: CGAffineTransform = .identity) -> PKStroke {
        let samples = [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 13), CGPoint(x: 90, y: 8)]
        let times = [0.0, 0.017, 0.2]
        let points = samples.enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: times[index], size: CGSize(width: 3, height: 3), opacity: 1,
                          force: CGFloat(index + 1) / 4, azimuth: 0.4, altitude: 1)
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()), transform: transform, mask: nil)
    }
    func testProcessingKeepsActualSampleTimesAndPressure() throws {
        let source = stroke()
        let result = try XCTUnwrap(StrokeProcessing.process(source, tool: .pen, width: 3, settings: EditorToolSettings(), shapeHeld: false))
        for index in 0..<source.path.count {
            XCTAssertEqual(result.path[index].timeOffset, source.path[index].timeOffset)
            XCTAssertEqual(result.path[index].force, source.path[index].force)
        }
        let reopened = try PKDrawing(data: PKDrawing(strokes: [result]).dataRepresentation())
        XCTAssertEqual(reopened.strokes.first?.path.count, source.path.count)
    }
    func testRecognitionUsesPageScaleAndRejectsNonfinitePoints() {
        let logical = [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 10), CGPoint(x: 90, y: 10)]
        for zoom: CGFloat in [0.1, 0.5, 1, 4] {
            let screen = logical.map { CGPoint(x: $0.x * zoom, y: $0.y * zoom) }
            XCTAssertEqual(CanvasTouchObserver.recognizeScreenPoints(screen, zoom: zoom), [logical[0], logical[2]])
        }
        XCTAssertNil(CanvasTouchObserver.recognizeScreenPoints(logical, zoom: 0))
        XCTAssertNil(ShapeRecognition.recognize([.zero, CGPoint(x: CGFloat.nan, y: 1)]))
    }
    func testFingerShapeObservationFollowsDrawingPolicy() {
        let observer = CanvasTouchObserver()
        XCTAssertTrue(observer.accepts(.pencil)); XCTAssertFalse(observer.accepts(.direct))
        observer.fingerDrawing = true
        XCTAssertTrue(observer.accepts(.direct)); XCTAssertFalse(observer.accepts(.indirectPointer))
    }
    func testRecoveredIntervalAndPressureProfiles() throws {
        XCTAssertNil(StrokeProcessing.stabilizationInterval(0))
        XCTAssertNil(StrokeProcessing.stabilizationInterval(.nan))
        XCTAssertEqual(try XCTUnwrap(StrokeProcessing.stabilizationInterval(0.5)), 0.04, accuracy: 1e-12)
        XCTAssertEqual(StrokeProcessing.stabilizationInterval(2), StrokeProcessing.stabilizationInterval(1))
        var settings = EditorToolSettings(); settings.penStyle = .brush
        settings.pressureSensitivity = 0
        let insensitive = try XCTUnwrap(StrokeProcessing.process(stroke(), tool: .pen, width: 3, settings: settings, shapeHeld: false))
        settings.pressureSensitivity = 1
        let sensitive = try XCTUnwrap(StrokeProcessing.process(stroke(), tool: .pen, width: 3, settings: settings, shapeHeld: false))
        XCTAssertLessThan(sensitive.path[1].size.width, insensitive.path[1].size.width)
        settings.stabilization = 0; settings.stabilizationByStyle = ["brush": 100]
        XCTAssertEqual(settings.stabilization(for: .pen), 100)
    }
    func testNativeRulerDoesNotConvertHeldMarkerIntoShape() {
        var settings = EditorToolSettings(); settings.rulerEnabled = true
        XCTAssertNil(StrokeProcessing.process(stroke(), tool: .marker, width: 3, settings: settings, shapeHeld: true))
    }
    func testLiveStabilizationKeepsPrefixAndReducesTremor() throws {
        let samples = (0..<40).map { index in
            PKStrokePoint(location: CGPoint(x: index * 2, y: index.isMultiple(of: 2) ? 48 : 52),
                          timeOffset: Double(index) / 120, size: CGSize(width: 3, height: 3),
                          opacity: 1, force: 0.5, azimuth: 0, altitude: .pi / 2)
        }
        func drawing(_ count: Int) -> PKStroke {
            PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: Array(samples.prefix(count)), creationDate: Date()))
        }
        var settings = EditorToolSettings(); settings.stabilization = 100
        let preview = try XCTUnwrap(StrokeProcessing.process(drawing(20), tool: .pen, width: 3, settings: settings, shapeHeld: false))
        let completed = try XCTUnwrap(StrokeProcessing.process(drawing(40), tool: .pen, width: 3, settings: settings, shapeHeld: false))
        for index in 0..<20 { XCTAssertEqual(preview.path[index].location, completed.path[index].location) }
        for style in [EditorToolSettings.PenStyle.fountain, .brush] {
            settings.penStyle = style
            let live = try XCTUnwrap(StrokeProcessing.process(drawing(20), tool: .pen, width: 3, settings: settings, shapeHeld: false))
            let final = try XCTUnwrap(StrokeProcessing.process(drawing(40), tool: .pen, width: 3, settings: settings, shapeHeld: false))
            for index in 0..<20 { XCTAssertEqual(live.path[index].size, final.path[index].size) }
        }
        let jitter = (20..<40).reduce(CGFloat.zero) { $0 + abs(completed.path[$1].location.y - 50) }
        XCTAssertLessThan(jitter, 10)
        settings.stabilization = 0
        let direct = try XCTUnwrap(StrokeProcessing.process(drawing(40), tool: .pen, width: 3, settings: settings, shapeHeld: false))
        XCTAssertEqual(direct.path.map(\.location), samples.map(\.location))
    }

    func testPressureAndTiltCanBeDisabledIndependentlyAndPersist() throws {
        var settings = EditorToolSettings(); settings.pressureEnabled = true; settings.tiltEnabled = false
        let pressure = try XCTUnwrap(StrokeProcessing.process(stroke(), tool: .pen, width: 3, settings: settings, shapeHeld: false))
        XCTAssertLessThan(pressure.path[0].size.width, pressure.path[2].size.width)
        XCTAssertTrue(pressure.path.allSatisfy { $0.altitude == .pi / 2 })
        settings.pressureEnabled = false
        let fixed = try XCTUnwrap(StrokeProcessing.process(stroke(), tool: .pen, width: 3, settings: settings, shapeHeld: false))
        XCTAssertTrue(fixed.path.allSatisfy { $0.size == CGSize(width: 3, height: 3) && $0.force == 1 })
        settings.tiltEnabled = true
        let tilted = try XCTUnwrap(StrokeProcessing.process(stroke(), tool: .pen, width: 3, settings: settings, shapeHeld: false))
        XCTAssertGreaterThan(tilted.path[0].size.width, fixed.path[0].size.width)
        XCTAssertEqual(try JSONDecoder().decode(EditorToolSettings.self, from: JSONEncoder().encode(settings)), settings)
    }

}

@Suite(.serialized)
@MainActor
struct NativeInkContinuityTests {
    @Test(arguments: [DrawingToolKind.pen, .marker, .pencil, .fountainPen])
    func freehandKeepsNativeStrokeThroughPenUpAndSave(tool: DrawingToolKind) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let preferences = try #require(UserDefaults(suiteName: root.lastPathComponent))
        defer {
            preferences.removePersistentDomain(forName: root.lastPathComponent)
            try? FileManager.default.removeItem(at: root)
        }
        let store = LibraryStore(root: root)
        await store.load()
        let created = await store.create()
        let id = try #require(created)
        let session = EditorSession(store: store, noteID: id, preferences: preferences)
        await session.open()
        session.selectedTool = tool
        session.toolSettings.penStyle = .brush
        session.toolSettings.stabilization = 100
        session.canvas.tool = session.tool
        let coordinator = WritingCanvas.Coordinator(session: session, zoomWindow: false)
        let view = PageScrollView(canvas: session.canvas)
        coordinator.container = view
        coordinator.pageID = session.page?.id
        let ink = try #require(session.tool as? PKInkingTool)
        let points = (0..<8).map { index in
            PKStrokePoint(location: CGPoint(x: 20 + index * 8, y: 40 + index % 3),
                          timeOffset: Double(index) / 120, size: CGSize(width: 2 + index, height: 3),
                          opacity: 0.8, force: 0.4, azimuth: 0.5, altitude: 1)
        }
        let stroke = PKStroke(ink: PKInk(ink.inkType, color: ink.color),
                              path: PKStrokePath(controlPoints: points, creationDate: Date()))
        coordinator.canvasViewDidBeginUsingTool(session.canvas)
        coordinator.previewSamples(points)
        #expect(!view.shapePreviewActive)
        #expect(view.liveInk.isHidden)
        #expect(session.drawing.strokes.isEmpty)
        session.canvas.drawing = PKDrawing(strokes: [stroke])
        let native = session.canvas.drawing.dataRepresentation()
        coordinator.canvasViewDrawingDidChange(session.canvas)
        coordinator.canvasViewDidEndUsingTool(session.canvas)
        try await Task.sleep(for: .milliseconds(100))
        #expect(session.canvas.drawing.dataRepresentation() == native)
        #expect(session.drawing.dataRepresentation() == native)
        #expect(view.liveInk.isHidden)
        #expect(view.compositedInk.isHidden)
        #expect(await session.flush())
        let reopened = EditorSession(store: store, noteID: id, preferences: preferences)
        await reopened.open()
        // PencilKit may normalize archive metadata on decode; compare the ink itself.
        #expect(reopened.drawing.strokes.count == 1)
        let savedStroke = try #require(reopened.drawing.strokes.first)
        #expect(savedStroke.ink.inkType == stroke.ink.inkType)
        #expect(savedStroke.ink.color.presetHex == stroke.ink.color.presetHex)
        #expect(savedStroke.randomSeed == stroke.randomSeed)
        #expect(savedStroke.transform == stroke.transform)
        #expect(savedStroke.path.count == stroke.path.count)
        for (saved, original) in zip(savedStroke.path, stroke.path) {
            #expect(saved.location == original.location)
            #expect(saved.size == original.size)
            #expect(abs(saved.force - original.force) < 0.0001)
            #expect(abs(saved.timeOffset - original.timeOffset) < 0.0001)
        }
        coordinator.cancelStroke()
        view.detachInteractions()
        view.pageTurn.detach()
    }

    @available(iOS 16.4, *)
    @Test
    func eraserOptionsConfigureNativeToolWithoutReselecting() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let preferences = try #require(UserDefaults(suiteName: root.lastPathComponent))
        defer {
            preferences.removePersistentDomain(forName: root.lastPathComponent)
            try? FileManager.default.removeItem(at: root)
        }
        let store = LibraryStore(root: root)
        await store.load()
        let created = await store.create()
        let session = EditorSession(store: store, noteID: try #require(created), preferences: preferences)
        session.selectedTool = .eraser
        session.toolSettings.eraserMode = .stroke
        let coordinator = WritingCanvas.Coordinator(session: session, zoomWindow: false)
        coordinator.configureTool(session.canvas)
        #expect((session.canvas.tool as? PKEraserTool)?.eraserType == .vector)
        session.toolSettings.eraserMode = .pixel
        session.toolSettings.eraserWidth = 30
        coordinator.configureTool(session.canvas)
        let eraser = try #require(session.canvas.tool as? PKEraserTool)
        #expect(eraser.eraserType != .vector)
        #expect(eraser.width == 30)
        session.toolSettings.eraserWidth = 50
        coordinator.configureTool(session.canvas)
        #expect((session.canvas.tool as? PKEraserTool)?.width == 50)
    }
}

@Suite(.serialized)
@MainActor
struct ToolCustomizationAndSelectionTests {
    @available(iOS 17.0, *)
    @Test func nativePresetsAndMarkerSettingsApplyImmediatelyAndPersist() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let preferences = try #require(UserDefaults(suiteName: root.lastPathComponent))
        defer { preferences.removePersistentDomain(forName: root.lastPathComponent); try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let session = EditorSession(store: store, noteID: UUID(), preferences: preferences)
        let coordinator = WritingCanvas.Coordinator(session: session, zoomWindow: false)
        for (preset, type) in [(EditorToolSettings.PenStyle.ballpoint, PKInk.InkType.monoline), (.fountain, .fountainPen), (.brush, .pen)] {
            session.toolSettings.applyPenPreset(preset)
            coordinator.configureTool(session.canvas)
            #expect((session.canvas.tool as? PKInkingTool)?.inkType == type)
            session.toolSettings.pressureEnabled = false
            coordinator.configureTool(session.canvas)
            #expect((session.canvas.tool as? PKInkingTool)?.inkType == .monoline)
        }
        session.selectedTool = .marker
        session.toolSettings.markerTiltEnabled = true
        coordinator.configureTool(session.canvas)
        #expect((session.canvas.tool as? PKInkingTool)?.inkType == .marker)
        session.toolSettings.markerTiltEnabled = false
        coordinator.configureTool(session.canvas)
        let round = try #require(session.canvas.tool as? PKInkingTool)
        #expect(round.inkType == .monoline)
        #expect(abs(round.color.cgColor.alpha - 0.3) < 0.001)
        let reopened = EditorSession(store: store, noteID: session.noteID, preferences: preferences)
        #expect(reopened.toolSettings == session.toolSettings)
        #expect((reopened.tool as? PKInkingTool)?.inkType == .monoline)
        #expect((reopened.tool as? PKInkingTool)?.color.cgColor.alpha == round.color.cgColor.alpha)
    }

    private func stroke(y: CGFloat) -> PKStroke {
        let points = [CGFloat(40), 60, 80].enumerated().map { index, x in
            PKStrokePoint(location: CGPoint(x: x, y: y), timeOffset: Double(index) / 10,
                          size: CGSize(width: 8, height: 8), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))
    }

    @Test func selectionPreviewMovesVisibleInkBeforeCommitWithoutChangingDrawing() throws {
        var page = NotePage(noteID: UUID(), index: 0, format: .a4Portrait, template: .blank, drawingResourceID: "ink.drawing")
        page.width = 300; page.height = 200
        let drawing = PKDrawing(strokes: [stroke(y: 40), stroke(y: 150)])
        let original = drawing.dataRepresentation()
        let snapshot = SelectionMoveSnapshot(page: page, drawing: drawing,
                                             path: UIBezierPath(rect: CGRect(x: 20, y: 20, width: 80, height: 60)), settings: EditorToolSettings())
        #expect(snapshot.strokeIndices == [0])
        let preview = SelectionDragPreview(frame: CGRect(x: 0, y: 0, width: 300, height: 200), page: page,
                                           artwork: nil, drawing: drawing, snapshot: snapshot, zoom: 1, offset: .zero)
        let image = preview.foreground.image
        let oldFrame = preview.foreground.frame
        #expect(preview.move(by: CGPoint(x: 80, y: 40)) == CGPoint(x: 80, y: 40))
        #expect(preview.foreground.frame.origin == CGPoint(x: oldFrame.minX + 80, y: oldFrame.minY + 40))
        #expect(preview.foreground.image === image, "Do not rasterize every drag update")
        #expect(drawing.dataRepresentation() == original, "Preview must not mutate persisted ink or undo")
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: preview.bounds.size, format: format).image { preview.layer.render(in: $0.cgContext) }
        #expect(try intensity(rendered, x: 60, y: 40) > 240, "Selected ink must disappear from its old location")
        #expect(try intensity(rendered, x: 140, y: 80) < 80, "Ink must be visible at the drag location before lift")
        #expect(try intensity(rendered, x: 60, y: 150) < 80, "Unselected ink must stay in place")
        let limited = preview.move(by: CGPoint(x: 10000, y: -10000))
        #expect(abs(snapshot.bounds.maxX + limited.x - 300) < 0.001)
        #expect(abs(snapshot.bounds.minY + limited.y) < 0.001)
    }

    @Test func selectionPreviewAccountsForZoomOffsetFiltersAndCancel() throws {
        var page = NotePage(noteID: UUID(), index: 0, format: .a4Portrait, template: .blank, drawingResourceID: "ink.drawing")
        page.width = 300; page.height = 200
        let note = PageElement(kind: .stickyNote, x: 40, y: 40, width: 80, height: 60, text: "Move")
        page.elements = [note]
        var settings = EditorToolSettings(); settings.includeHandwriting = false
        let drawing = PKDrawing(strokes: [stroke(y: 40)])
        let snapshot = SelectionMoveSnapshot(page: page, drawing: drawing,
                                             path: UIBezierPath(rect: CGRect(x: 10, y: 10, width: 150, height: 100)), settings: settings)
        #expect(snapshot.strokeIndices.isEmpty)
        #expect(snapshot.elementIDs == [note.id])
        let preview = SelectionDragPreview(frame: CGRect(x: 0, y: 0, width: 300, height: 200), page: page,
                                           artwork: nil, drawing: drawing, snapshot: snapshot, zoom: 2, offset: CGPoint(x: 30, y: 10))
        let initial = preview.foreground.frame
        preview.move(by: CGPoint(x: 40, y: 30))
        #expect(preview.delta == CGPoint(x: 20, y: 15))
        #expect(preview.foreground.frame.minX == initial.minX + 40)
        preview.move(by: .zero)
        #expect(preview.foreground.frame == initial)
        #expect(page.elements == [note])
    }

    @Test func eraserCursorTracksPositionAndZoomWithoutConsumingNativeErasing() throws {
        let canvas = PKCanvasView()
        let view = PageScrollView(canvas: canvas)
        view.eraserCursorEnabled = true; view.eraserCursorWidth = 24
        view.showEraserCursor(at: CGPoint(x: 100, y: 80))
        let circle = try #require(view.layer.sublayers?.compactMap { $0 as? CAShapeLayer }.first { $0.path?.boundingBox.midX == 100 })
        #expect(circle.path?.boundingBox.width == max(6, 24 * canvas.zoomScale))
        view.showEraserCursor(at: CGPoint(x: 120, y: 90))
        #expect(circle.path?.boundingBox.midX == 120)
        view.eraserCursorEnabled = false
        #expect(circle.path == nil)
        view.touchObserver.observeEraser = true
        #expect(!view.touchObserver.canPrevent(canvas.drawingGestureRecognizer))
        view.detachInteractions(); view.pageTurn.detach()
    }

    @Test func fastSelectionPickupUsesContactOriginAndCancellationPreservesSelection() {
        let view = PageSelectionView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        var pickups = 0
        var commits: [CGPoint] = []
        var cancelled = 0
        view.moveBegan = { _ in pickups += 1 }
        view.moveChanged = { $0 }
        view.moveCancelled = { cancelled += 1 }
        view.moved = { _, delta in commits.append(delta) }
        view.updateDrag(state: .began, point: CGPoint(x: 40, y: 30), translation: CGPoint(x: 10, y: 0))
        view.updateDrag(state: .changed, point: CGPoint(x: 100, y: 30), translation: CGPoint(x: 70, y: 0))
        view.updateDrag(state: .changed, point: CGPoint(x: 100, y: 100), translation: CGPoint(x: 70, y: 70))
        view.updateDrag(state: .changed, point: CGPoint(x: 30, y: 100), translation: CGPoint(x: 0, y: 70))
        view.updateDrag(state: .ended, point: CGPoint(x: 30, y: 30), translation: .zero)
        // The contact began inside, but recognition arrived after moving outside.
        view.updateDrag(state: .began, point: CGPoint(x: 160, y: 160), translation: CGPoint(x: 100, y: 100))
        #expect(pickups == 1)
        #expect(commits.isEmpty)
        view.updateDrag(state: .cancelled, point: CGPoint(x: 160, y: 160), translation: CGPoint(x: 100, y: 100))
        #expect(cancelled > 0)
        #expect(commits.isEmpty)
        view.updateDrag(state: .began, point: CGPoint(x: 160, y: 160), translation: CGPoint(x: 100, y: 100))
        view.updateDrag(state: .ended, point: CGPoint(x: 170, y: 170), translation: CGPoint(x: 110, y: 110))
        #expect(pickups == 2)
        #expect(commits == [CGPoint(x: 110, y: 110)])
    }

    private func intensity(_ image: UIImage, x: Int, y: Int) throws -> UInt8 {
        let source = try #require(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: source.width * source.height * 4)
        let context = try #require(CGContext(data: &bytes, width: source.width, height: source.height,
                                            bitsPerComponent: 8, bytesPerRow: source.width * 4,
                                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        return bytes[(y * source.width + x) * 4]
    }
}
