import UIKit
import PencilKit

// Observe Pencil holds without competing with PencilKit's drawing recognizer.
final class CanvasTouchObserver: UIGestureRecognizer {
    var erasing = false
    var observeEraser = false
    var eraserPointer: ((CGPoint?) -> Void)?
    var fingerDrawing = false
    var observeShapes = true
    var observeWriting = false
    var erased: (([CGPoint]) -> Void)?
    var held: (([CGPoint]) -> Void)?
    var adjustedShape: ((CGPoint) -> Void)?
    var sampled: (([PKStrokePoint]) -> Void)?
    private var samples: [PKStrokePoint] = []
    private var startedAt: TimeInterval = 0
    var holdCancelled: (() -> Void)?
    var cancelledStroke: (() -> Void)?
    var beganStroke: (() -> Void)?
    var pageID: UUID? { didSet { if oldValue != pageID { timer?.invalidate(); heldShape = false; holdCancelled?() } } }
    private var sourcePageID: UUID?
    private var points: [CGPoint] = []
    private var stationary = CGPoint.zero
    private var timer: Timer?
    private var heldShape = false

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { erasing }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard event.allTouches?.count == 1, let touch = touches.first,
              accepts(touch.type), erasing || observeShapes || observeWriting || observeEraser else {
            if sourcePageID != nil { timer?.invalidate(); holdCancelled?(); cancelledStroke?() }
            state = state == .possible ? .failed : .cancelled; return
        }
        let point = touch.location(in: view?.superview)
        if observeEraser { eraserPointer?(point) }
        sourcePageID = pageID
        points = [point]; stationary = point; heldShape = false
        startedAt = touch.timestamp; samples = []
        beganStroke?()
        collect([touch])
        if erasing { state = .began }
        else if observeShapes { scheduleHold() }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard sourcePageID == pageID, event.allTouches?.count == 1, let touch = touches.first else {
            eraserPointer?(nil)
            timer?.invalidate(); holdCancelled?(); cancelledStroke?()
            state = state == .possible ? .failed : .cancelled; return
        }
        guard accepts(touch.type) else { return }
        guard erasing || observeShapes || observeWriting || observeEraser else { return }
        // Keep predicted positions out of recognized shapes and saved ink.
        let samples = event.coalescedTouches(for: touch) ?? [touch]
        points.append(contentsOf: samples.map { $0.location(in: view?.superview) })
        if !heldShape { collect(samples) }
        let point = touch.location(in: view?.superview)
        if observeEraser { eraserPointer?(point) }
        if erasing { state = .changed; return }
        if heldShape {
            adjustedShape?(point)
            return
        }
        if observeShapes && hypot(point.x - stationary.x, point.y - stationary.y) > 6 {
            stationary = point; scheduleHold()
        }
    }
    private func collect(_ touches: [UITouch]) {
        guard observeWriting, let canvas = view as? PKCanvasView, canvas.zoomScale > 0,
              let ink = canvas.tool as? PKInkingTool else { return }
        for touch in touches {
            let time = touch.timestamp - startedAt
            guard samples.last.map({ time > $0.timeOffset }) ?? true else { continue }
            let point = touch.location(in: view?.superview)
            let pressure = touch.type == .pencil && touch.maximumPossibleForce > 0
                ? min(1, max(0, touch.force / touch.maximumPossibleForce)) : 0.5
            samples.append(PKStrokePoint(
                location: CGPoint(x: (point.x + canvas.contentOffset.x) / canvas.zoomScale,
                                  y: (point.y + canvas.contentOffset.y) / canvas.zoomScale),
                timeOffset: time, size: CGSize(width: ink.width, height: ink.width), opacity: 1,
                force: pressure, azimuth: touch.type == .pencil ? touch.azimuthAngle(in: canvas) : 0,
                altitude: touch.type == .pencil ? touch.altitudeAngle : .pi / 2))
        }
        sampled?(samples)
    }
    func accepts(_ type: UITouch.TouchType) -> Bool {
        type == .pencil || (fingerDrawing && type == .direct)
    }
    func recognizedShape() -> [CGPoint]? {
        let zoom = (view as? PKCanvasView)?.zoomScale ?? 1
        return Self.recognizeScreenPoints(points, zoom: zoom)
    }
    static func recognizeScreenPoints(_ points: [CGPoint], zoom: CGFloat) -> [CGPoint]? {
        guard zoom.isFinite, zoom > 0 else { return nil }
        return ShapeRecognition.recognize(points.map { CGPoint(x: $0.x / zoom, y: $0.y / zoom) })
    }
    private func scheduleHold() {
        timer?.invalidate()
        timer = Timer(timeInterval: 0.65, repeats: false) { [weak self] _ in
            guard let self, self.state == .possible, self.points.count >= 3,
                  self.sourcePageID == self.pageID,
                  self.recognizedShape() != nil else { return }
            self.heldShape = true
            self.held?(self.points)
            UISelectionFeedbackGenerator().selectionChanged()
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        timer?.invalidate()
        eraserPointer?(nil)
        guard sourcePageID == pageID else { holdCancelled?(); state = state == .possible ? .failed : .cancelled; return }
        if let touch = touches.first {
            let point = touch.location(in: view?.superview)
            points.append(point)
            if heldShape { adjustedShape?(point) }
            else { collect([touch]) }
        }
        if erasing { erased?(points); state = .ended }
        else {
            state = .failed
        }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        eraserPointer?(nil)
        timer?.invalidate(); holdCancelled?(); cancelledStroke?()
        state = state == .possible ? .failed : .cancelled
    }
    override func reset() { super.reset(); eraserPointer?(nil); timer?.invalidate(); timer = nil; points = []; samples = []; sourcePageID = nil; heldShape = false }
}
