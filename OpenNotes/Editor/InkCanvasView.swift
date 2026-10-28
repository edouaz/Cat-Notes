import UIKit

protocol InkCanvasViewDelegate: UIScrollViewDelegate {
    func canvasViewDrawingDidChange(_ canvas: InkCanvasView)
    func canvasViewDidBeginUsingTool(_ canvas: InkCanvasView)
    func canvasViewDidEndUsingTool(_ canvas: InkCanvasView)
    func canvasViewDidFinishRendering(_ canvas: InkCanvasView)
}
extension InkCanvasViewDelegate {
    func canvasViewDrawingDidChange(_ canvas: InkCanvasView) {}
    func canvasViewDidBeginUsingTool(_ canvas: InkCanvasView) {}
    func canvasViewDidEndUsingTool(_ canvas: InkCanvasView) {}
    func canvasViewDidFinishRendering(_ canvas: InkCanvasView) {}
}

class InkTool {}
final class InkInkingTool: InkTool {
    let inkType: InkInk.InkType
    let color: UIColor
    let width: CGFloat
    init(_ inkType: InkInk.InkType, color: UIColor, width: CGFloat) {
        self.inkType = inkType; self.color = color; self.width = width
    }
}
final class InkEraserTool: InkTool {
    enum EraserType { case bitmap, vector }
    let eraserType: EraserType
    let width: CGFloat
    init(_ type: EraserType, width: CGFloat = 24) { eraserType = type; self.width = width }
}
final class InkLassoTool: InkTool {}

// The same accumulator is used by UIKit input and deterministic capture tests.
struct InkSampleBuffer {
    private(set) var samples: [InkStrokePoint] = []
    private(set) var predictions: [InkStrokePoint] = []
    private var estimates: [Int: Int] = [:]
    mutating func append(_ sample: InkStrokePoint, estimate: Int? = nil) {
        guard sample.location.x.isFinite, sample.location.y.isFinite, sample.timeOffset.isFinite,
              sample.timeOffset >= 0, sample.force.isFinite else { return }
        if let estimate, estimates[estimate] != nil { _ = update(sample, estimate: estimate); return }
        if let last = samples.last {
            guard sample.timeOffset >= last.timeOffset else { return }
            if sample == last { return }
        }
        if let estimate { estimates[estimate] = samples.count }
        samples.append(sample)
    }
    mutating func update(_ sample: InkStrokePoint, estimate: Int) -> Bool {
        guard let index = estimates[estimate], sample.location.x.isFinite, sample.location.y.isFinite,
              sample.force.isFinite else { return false }
        // Keep the measured chronology when UIKit updates only estimated properties.
        var revised = sample; revised.timeOffset = samples[index].timeOffset
        samples[index] = revised
        return true
    }
    mutating func predict(_ samples: [InkStrokePoint]) { predictions = samples }
    mutating func clearPredictions() { predictions = [] }
    mutating func cancel() { self = Self() }
    func stroke(geometry: [InkStrokePoint], ink: InkInk, createdAt: Date, id: UUID,
                tool: DrawingToolKind, width: Double, settings: EditorToolSettings) -> InkStroke? {
        guard !samples.isEmpty, !geometry.isEmpty else { return nil }
        let source = InkStroke(ink: ink, path: InkStrokePath(controlPoints: geometry, creationDate: createdAt),
                               rawSamples: geometry, id: id)
        guard var result = StrokeProcessing.process(source, tool: tool, width: width, settings: settings, shapeHeld: false) else { return nil }
        result.rawSamples = samples
        return result
    }
}

final class InkCanvasView: UIScrollView, UIScrollViewDelegate {
    enum DrawingPolicy { case anyInput, pencilOnly }
    weak var inkDelegate: InkCanvasViewDelegate?
    var onCommit: ((InkDrawing, String) -> Void)?
    var onCompletedStroke: ((InkStroke) -> InkDrawing?)?
    var onStrokeBegan: (() -> Void)?
    var canCircleLongPress: ((CGPoint) -> Bool)?
    var onCircleLongPress: ((CGPoint) -> Bool)?
    var onEstimatedStrokeUpdate: ((InkDrawing) -> Void)?
    let inkContentView = InkContentView()
    let drawingGestureRecognizer = UIGestureRecognizer()
    var drawingPolicy = DrawingPolicy.pencilOnly
    var selectedTool = DrawingToolKind.pen
    var settings = EditorToolSettings()
    var tool: InkTool = InkInkingTool(.pen, color: .black, width: 3)
    var isRulerActive = false
    private let history = UndoManager()
    override var undoManager: UndoManager? { history }
    override var canBecomeFirstResponder: Bool { true }
    var drawing = InkDrawing() {
        didSet { inkContentView.install(drawing); inkDelegate?.canvasViewDidFinishRendering(self) }
    }
    func setPageSize(_ size: CGSize) {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              inkContentView.bounds.size != size else { return }
        cancelStroke()
        let previousZoom = zoomScale, previousMinimum = minimumZoomScale
        minimumZoomScale = min(1, previousMinimum)
        setZoomScale(1, animated: false)
        inkContentView.bounds = CGRect(origin: .zero, size: size)
        inkContentView.frame = CGRect(origin: .zero, size: size)
        contentSize = size
        minimumZoomScale = previousMinimum
        setZoomScale(previousZoom, animated: false)
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { inkContentView }
    var hasActiveStroke: Bool { activeTouch != nil }
    private var activeTouch: UITouch?
    private var buffer = InkSampleBuffer()
    private var startedAt: TimeInterval = 0
    private var createdAt = Date()
    private var strokeID = UUID()
    private var capturedSettings = EditorToolSettings()
    private var capturedTool = DrawingToolKind.pen
    private var capturedInk: InkInkingTool?
    private var capturedEraser: InkEraserTool?
    private var lastStationary = CGPoint.zero
    private var holdTimer: Timer?
    private var heldAdjustment: ShapeRecognition.Adjustment?
    private var heldPoints: [CGPoint]?
    private var awaitingCircle = false
    private var circleStart = CGPoint.zero
    private var pendingEstimateStroke: InkStroke?
    private let hoverLayer = CAShapeLayer()
    private let circleHold = UILongPressGestureRecognizer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false; backgroundColor = .clear
        delegate = self
        delaysContentTouches = false
        panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        panGestureRecognizer.minimumNumberOfTouches = 2
        inkContentView.owner = self; addSubview(inkContentView)
        circleHold.minimumPressDuration = 0.55
        circleHold.addTarget(self, action: #selector(circlePressed(_:)))
        circleHold.delegate = inkContentView
        inkContentView.addGestureRecognizer(circleHold)
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:)))
        hover.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        inkContentView.addGestureRecognizer(hover)
        hoverLayer.fillColor = UIColor.clear.cgColor
        hoverLayer.strokeColor = UIColor.label.cgColor
        hoverLayer.lineWidth = 0.7
        hoverLayer.isHidden = true
        inkContentView.layer.addSublayer(hoverLayer)
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted), name: UIApplication.willResignActiveNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { NotificationCenter.default.removeObserver(self) }
    override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { cancelStroke() } }
    @objc private func interrupted() { cancelStroke() }
    func cancelActiveStroke() { cancelStroke() }
    func cancelStroke() {
        let hadTouch = activeTouch != nil
        activeTouch = nil; awaitingCircle = false
        holdTimer?.invalidate(); holdTimer = nil
        heldAdjustment = nil; heldPoints = nil; capturedInk = nil; capturedEraser = nil
        buffer.cancel(); pendingEstimateStroke = nil
        inkContentView.preview.path = nil; hoverLayer.isHidden = true
        if hadTouch { inkDelegate?.canvasViewDidEndUsingTool(self) }
    }
    func accepts(_ type: UITouch.TouchType) -> Bool {
        type == .pencil || (drawingPolicy == .anyInput && type == .direct)
    }
    fileprivate func accepts(_ touch: UITouch) -> Bool { accepts(touch.type) }
    fileprivate func begin(_ touches: Set<UITouch>, event: UIEvent?) {
        guard drawingGestureRecognizer.isEnabled, activeTouch == nil,
              let touch = touches.first(where: accepts),
              tool is InkInkingTool || tool is InkEraserTool else { return }
        if touch.type == .direct, (event?.allTouches?.filter { $0.type == .direct }.count ?? 1) > 1 { return }
        let point = touch.location(in: inkContentView)
        guard inkContentView.bounds.contains(point) else { return }
        activeTouch = touch; startedAt = touch.timestamp; createdAt = Date(); strokeID = UUID()
        buffer.cancel(); pendingEstimateStroke = nil
        capturedSettings = settings; capturedTool = selectedTool
        capturedInk = tool as? InkInkingTool; capturedEraser = tool as? InkEraserTool
        heldPoints = nil; heldAdjustment = nil
        hoverLayer.isHidden = true; lastStationary = point
        awaitingCircle = canCircleLongPress?(point) == true
        circleStart = point
        if !awaitingCircle { beginDrawing(touch, event: event) }
    }
    private func beginDrawing(_ touch: UITouch, event: UIEvent?) {
        onStrokeBegan?()
        inkDelegate?.canvasViewDidBeginUsingTool(self)
        collect(touch, event: event, predicting: false)
        showPreview()
        scheduleHold()
    }
    fileprivate func move(_ touches: Set<UITouch>, event: UIEvent?) {
        guard let activeTouch, touches.contains(activeTouch) else { return }
        if activeTouch.type == .direct, (event?.allTouches?.filter { $0.type == .direct }.count ?? 1) > 1 { cancelStroke(); return }
        let location = activeTouch.location(in: inkContentView)
        if awaitingCircle {
            guard hypot(location.x - circleStart.x, location.y - circleStart.y) * zoomScale > 6 else { return }
            awaitingCircle = false; beginDrawing(activeTouch, event: event)
        }
        if let adjustment = heldAdjustment {
            heldPoints = adjustment.points(at: location)
        } else {
            collect(activeTouch, event: event, predicting: true)
            if hypot(location.x - lastStationary.x, location.y - lastStationary.y) * zoomScale > 3 {
                lastStationary = location; scheduleHold()
            }
        }
        showPreview()
    }
    fileprivate func end(_ touches: Set<UITouch>, event: UIEvent?) {
        guard let activeTouch, touches.contains(activeTouch) else { return }
        defer {
            self.activeTouch = nil; holdTimer?.invalidate(); holdTimer = nil
            heldAdjustment = nil; heldPoints = nil; awaitingCircle = false
            inkContentView.preview.path = nil
            inkDelegate?.canvasViewDidEndUsingTool(self)
        }
        if awaitingCircle { return }
        if let adjustment = heldAdjustment { heldPoints = adjustment.points(at: activeTouch.location(in: inkContentView)) }
        else { collect(activeTouch, event: event, predicting: false) }
        buffer.clearPredictions()
        if let eraser = capturedEraser {
            let mode: EditorToolSettings.EraserMode = eraser.eraserType == .vector ? capturedSettings.eraserMode : .pixel
            let result = EraserEditing.erase(drawing, along: buffer.samples.map(\.location), width: Double(eraser.width), mode: mode)
            if result.dataRepresentation() != drawing.dataRepresentation() { commit(result, name: "Erase") }
        } else if let stroke = makeStroke(includePredictions: false) {
            let result = heldPoints == nil ? onCompletedStroke?(stroke) : nil
            commit(result ?? InkDrawing(strokes: drawing.strokes + [stroke]), name: result == nil ? "Draw" : "Scribble erase")
            if heldPoints == nil, drawing.strokes.contains(where: { $0.id == stroke.id }) { pendingEstimateStroke = stroke }
        }
    }
    private func commit(_ result: InkDrawing, name: String) {
        if let onCommit { onCommit(result, name) }
        else { drawing = result; inkDelegate?.canvasViewDrawingDidChange(self) }
    }
    private func sample(_ touch: UITouch) -> InkStrokePoint {
        let width = capturedInk?.width ?? capturedEraser?.width ?? 3
        let force: CGFloat = touch.type == .pencil && touch.maximumPossibleForce > 0
            ? min(1, max(0, touch.force / touch.maximumPossibleForce)) : 0.5
        return InkStrokePoint(location: touch.location(in: inkContentView), timeOffset: max(0, touch.timestamp - startedAt),
                              size: CGSize(width: width, height: width), opacity: 1, force: force,
                              azimuth: touch.type == .pencil ? touch.azimuthAngle(in: inkContentView) : 0,
                              altitude: touch.type == .pencil ? touch.altitudeAngle : .pi / 2)
    }
    private func collect(_ touch: UITouch, event: UIEvent?, predicting: Bool) {
        buffer.clearPredictions()
        var measured = event?.coalescedTouches(for: touch) ?? [touch]
        if !measured.contains(where: { $0 === touch }) { measured.append(touch) }
        for item in measured.sorted(by: { $0.timestamp < $1.timestamp }) {
            buffer.append(sample(item), estimate: item.estimationUpdateIndex?.intValue)
        }
        if predicting { buffer.predict((event?.predictedTouches(for: touch) ?? []).map(sample)) }
    }
    fileprivate func cancel(_ touches: Set<UITouch>) {
        guard let activeTouch, touches.contains(activeTouch) else { return }
        cancelStroke()
    }
    fileprivate func estimatesUpdated(_ touches: Set<UITouch>) {
        var changed = false
        for touch in touches {
            guard let index = touch.estimationUpdateIndex?.intValue else { continue }
            changed = buffer.update(sample(touch), estimate: index) || changed
        }
        guard changed else { return }
        if activeTouch != nil { showPreview() }
        else if heldPoints == nil, let original = pendingEstimateStroke,
                let index = drawing.strokes.firstIndex(where: { $0.id == original.id }),
                let corrected = makeStroke(includePredictions: false) {
            var result = drawing; result.strokes[index] = corrected
            if let onEstimatedStrokeUpdate { onEstimatedStrokeUpdate(result) }
            else { drawing = result; inkDelegate?.canvasViewDrawingDidChange(self) }
            pendingEstimateStroke = corrected
        }
    }
    private func makeStroke(includePredictions: Bool) -> InkStroke? {
        guard let ink = capturedInk, !buffer.samples.isEmpty else { return nil }
        var samples = buffer.samples
        if let heldPoints {
            samples = heldPoints.enumerated().map { index, point in
                var value = buffer.samples[min(index, buffer.samples.count - 1)]
                value.location = point
                value.timeOffset = Double(index) / Double(max(1, heldPoints.count - 1)) * (buffer.samples.last?.timeOffset ?? 0)
                return value
            }
        } else if includePredictions { samples += buffer.predictions }
        if isRulerActive, let first = samples.first, let last = samples.last, samples.count > 1 {
            samples = samples.enumerated().map { index, value in
                var value = value
                let t = CGFloat(index) / CGFloat(samples.count - 1)
                value.location = CGPoint(x: first.location.x + (last.location.x - first.location.x) * t,
                                         y: first.location.y + (last.location.y - first.location.y) * t)
                return value
            }
        }
        var processingSettings = capturedSettings
        if heldPoints != nil { processingSettings.setStabilization(0, for: capturedTool) }
        return buffer.stroke(geometry: samples, ink: InkInk(ink.inkType, color: ink.color), createdAt: createdAt,
                             id: strokeID, tool: capturedTool, width: Double(ink.width), settings: processingSettings)
    }
    private func showPreview() {
        guard let stroke = makeStroke(includePredictions: true) else { return }
        inkContentView.show(stroke)
    }
    private func scheduleHold() {
        holdTimer?.invalidate()
        guard capturedInk != nil, capturedSettings.shapeRecognitionEnabled, !isRulerActive else { return }
        holdTimer = Timer(timeInterval: 0.55, repeats: false) { [weak self] _ in
            guard let self, let touch = self.activeTouch, !self.awaitingCircle,
                  let points = ShapeRecognition.recognize(self.buffer.samples.map(\.location)) else { return }
            let recognized = self.capturedSettings.shapeAngleSnap == true ? StrokeProcessing.snappedLine(points) : points
            self.heldPoints = recognized
            self.heldAdjustment = ShapeRecognition.Adjustment(points: recognized, pointer: touch.location(in: self.inkContentView))
            self.buffer.clearPredictions(); self.showPreview()
            UISelectionFeedbackGenerator().selectionChanged()
        }
        if let holdTimer { RunLoop.main.add(holdTimer, forMode: .common) }
    }
    @objc private func circlePressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: inkContentView)
        if onCircleLongPress?(point) == true { cancelStroke() }
    }
    @objc private func hovered(_ gesture: UIHoverGestureRecognizer) {
        guard #available(iOS 16.1, *),
              activeTouch == nil, drawingGestureRecognizer.isEnabled, let ink = tool as? InkInkingTool,
              gesture.state != .ended, gesture.state != .cancelled else { hoverLayer.isHidden = true; return }
        if #available(iOS 17.5, *), !UIPencilInteraction.prefersHoverToolPreview { hoverLayer.isHidden = true; return }
        let point = gesture.location(in: inkContentView)
        guard inkContentView.bounds.contains(point) else { hoverLayer.isHidden = true; return }
        let radius = max(1 / max(0.1, zoomScale), ink.width / 2)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        hoverLayer.path = CGPath(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2), transform: nil)
        hoverLayer.strokeColor = ink.color.withAlphaComponent(0.8).cgColor
        hoverLayer.lineWidth = 1 / max(0.1, zoomScale); hoverLayer.isHidden = false
        CATransaction.commit()
    }
}

// Retained vector layers cache committed geometry; movement rebuilds only the live layer.
final class InkContentView: UIView, UIGestureRecognizerDelegate {
    weak var owner: InkCanvasView?
    let preview = CAShapeLayer()
    private var committed: [UUID: CAShapeLayer] = [:]
    private var installed: [UUID: InkStroke] = [:]
    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true; isOpaque = false; backgroundColor = .clear
        layer.addSublayer(preview)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func install(_ drawing: InkDrawing) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let ids = Set(drawing.strokes.map(\.id))
        for id in committed.keys.filter({ !ids.contains($0) }) { committed.removeValue(forKey: id)?.removeFromSuperlayer(); installed[id] = nil }
        for (order, stroke) in drawing.strokes.enumerated() {
            let shape: CAShapeLayer
            if let existing = committed[stroke.id] { shape = existing }
            else { shape = CAShapeLayer(); committed[stroke.id] = shape; layer.insertSublayer(shape, below: preview) }
            // The path object is cached until the immutable document stroke changes.
            if let previous = installed[stroke.id], previous.path.controlPoints == stroke.path.controlPoints,
               previous.style == stroke.style, previous.transform == stroke.transform,
               previous.ink.color.isEqual(stroke.ink.color), previous.ink.inkType == stroke.ink.inkType { }
            else { configure(shape, stroke: stroke); installed[stroke.id] = stroke }
            shape.zPosition = CGFloat(order)
        }
        preview.zPosition = CGFloat(drawing.strokes.count + 1)
        CATransaction.commit()
    }
    func show(_ stroke: InkStroke) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        configure(preview, stroke: stroke)
        CATransaction.commit()
    }
    private func configure(_ shape: CAShapeLayer, stroke: InkStroke) {
        shape.path = stroke.paintedPath
        shape.setAffineTransform(stroke.transform)
        shape.fillColor = stroke.ink.color.withAlphaComponent(stroke.ink.color.cgColor.alpha * (stroke.ink.inkType == .marker ? 0.3 : 1)).cgColor
        shape.fillRule = .nonZero
    }
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer is UILongPressGestureRecognizer {
            return owner?.canCircleLongPress?(gestureRecognizer.location(in: self)) == true
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { owner?.begin(touches, event: event) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { owner?.move(touches, event: event) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { owner?.end(touches, event: event) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { owner?.cancel(touches) }
    override func touchesEstimatedPropertiesUpdated(_ touches: Set<UITouch>) { owner?.estimatesUpdated(touches) }
}
