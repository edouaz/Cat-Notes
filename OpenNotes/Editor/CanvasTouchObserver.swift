import UIKit
import PencilKit

// Observe Pencil holds without competing with PencilKit's drawing recognizer.
final class CanvasTouchObserver: UIGestureRecognizer {
    var erasing = false
    var fingerDrawing = false
    var observeShapes = true
    var observeWriting = false
    var erased: (([CGPoint]) -> Void)?
    var held: (([CGPoint]) -> Void)?
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
              accepts(touch.type), erasing || observeShapes || observeWriting else {
            if sourcePageID != nil { timer?.invalidate(); holdCancelled?(); cancelledStroke?() }
            state = state == .possible ? .failed : .cancelled; return
        }
        let point = touch.location(in: view?.superview)
        sourcePageID = pageID
        points = [point]; stationary = point; heldShape = false
        beganStroke?()
        if erasing { state = .began }
        else if observeShapes { scheduleHold() }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard sourcePageID == pageID, event.allTouches?.count == 1, let touch = touches.first else {
            timer?.invalidate(); holdCancelled?(); cancelledStroke?()
            state = state == .possible ? .failed : .cancelled; return
        }
        guard erasing || observeShapes else { return }
        // Only observed samples enter recognition; PencilKit owns transient prediction.
        let samples = event.coalescedTouches(for: touch) ?? [touch]
        points.append(contentsOf: samples.map { $0.location(in: view?.superview) })
        let point = touch.location(in: view?.superview)
        if erasing { state = .changed; return }
        if observeShapes && hypot(point.x - stationary.x, point.y - stationary.y) > 6 {
            stationary = point; heldShape = false; holdCancelled?(); scheduleHold()
        }
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
        // OpenNotes choice: the dossier does not establish the runtime holdDelay.
        timer = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: false) { [weak self] _ in
            guard let self, self.state == .possible, self.points.count >= 3,
                  self.sourcePageID == self.pageID,
                  self.recognizedShape() != nil else { return }
            self.heldShape = true
            self.held?(self.points)
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        timer?.invalidate()
        guard sourcePageID == pageID else { holdCancelled?(); state = state == .possible ? .failed : .cancelled; return }
        if let touch = touches.first {
            let point = touch.location(in: view?.superview)
            points.append(point)
            if !erasing && hypot(point.x - stationary.x, point.y - stationary.y) > 6 { heldShape = false; holdCancelled?() }
        }
        if erasing { erased?(points); state = .ended }
        else {
            state = .failed
        }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        timer?.invalidate(); holdCancelled?(); cancelledStroke?()
        state = state == .possible ? .failed : .cancelled
    }
    override func reset() { super.reset(); timer?.invalidate(); timer = nil; points = []; sourcePageID = nil; heldShape = false }
}
