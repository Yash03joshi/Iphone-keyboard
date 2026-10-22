import MLKitDigitalInkRecognition
import UIKit

/// Captures finger strokes, draws them, and builds an ML Kit `Ink`.
/// Mirrors the Android `HandwritingView`.
final class HandwritingView: UIView {
    var onStrokesChanged: ((Int) -> Void)?
    /// Called once the user has stopped writing for `pauseDelay`.
    var onWritingPaused: (() -> Void)?
    var pauseDelay: TimeInterval = 0.9

    var inkColor: UIColor = .label {
        didSet { setNeedsDisplay() }
    }

    var strokeWidth: CGFloat = 6 {
        didSet { setNeedsDisplay() }
    }

    var strokeCount: Int { strokes.count }

    /// True while a finger is down mid-stroke.
    var isWriting: Bool { current != nil }

    private struct DrawnStroke {
        var path = UIBezierPath()
        var points: [StrokePoint] = []
    }

    private var strokes: [DrawnStroke] = []
    private var current: Int?
    private var pauseTimer: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = false
        contentMode = .redraw
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: HandwritingView, _) in
            view.setNeedsDisplay()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func buildInk() -> Ink {
        Ink(strokes: strokes.map { Stroke(points: $0.points) })
    }

    func clear() {
        cancelPause()
        strokes.removeAll()
        current = nil
        setNeedsDisplay()
        onStrokesChanged?(0)
    }

    /// Removes the oldest `count` strokes (the ones just recognized), keeping any strokes
    /// written while recognition was running.
    func removeFirstStrokes(_ count: Int) {
        guard count < strokes.count else {
            clear()
            return
        }
        strokes.removeFirst(count)
        if let index = current { current = index - count }
        setNeedsDisplay()
        onStrokesChanged?(strokes.count)
    }

    func undoStroke() {
        guard !strokes.isEmpty, current == nil else { return }
        cancelPause()
        strokes.removeLast()
        setNeedsDisplay()
        onStrokesChanged?(strokes.count)
        schedulePause()
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        cancelPause()
        let location = touch.location(in: self)
        var stroke = DrawnStroke()
        stroke.path.move(to: location)
        stroke.points.append(point(location, touch.timestamp))
        strokes.append(stroke)
        current = strokes.count - 1
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let index = current else { return }
        for sample in event?.coalescedTouches(for: touch) ?? [touch] {
            addPoint(sample.location(in: self), sample.timestamp, to: index)
        }
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let index = current else { return }
        // A single tap is still a valid stroke (e.g. a dot); addLine keeps it drawable.
        addPoint(touch.location(in: self), touch.timestamp, to: index)
        current = nil
        setNeedsDisplay()
        onStrokesChanged?(strokes.count)
        schedulePause()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let index = current { strokes.remove(at: index) }
        current = nil
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        inkColor.resolvedColor(with: traitCollection).setStroke()
        for stroke in strokes {
            stroke.path.lineWidth = strokeWidth
            stroke.path.lineCapStyle = .round
            stroke.path.lineJoinStyle = .round
            stroke.path.stroke()
        }
    }

    // MARK: Private

    private func addPoint(_ location: CGPoint, _ timestamp: TimeInterval, to index: Int) {
        strokes[index].path.addLine(to: location)
        strokes[index].points.append(point(location, timestamp))
    }

    // ML Kit expects wall-clock milliseconds; UITouch timestamps are seconds since boot.
    private func point(_ location: CGPoint, _ timestamp: TimeInterval) -> StrokePoint {
        let wall = Date().timeIntervalSince1970 - (ProcessInfo.processInfo.systemUptime - timestamp)
        return StrokePoint(x: Float(location.x), y: Float(location.y), t: Int(wall * 1000))
    }

    private func schedulePause() {
        guard pauseDelay > 0, !strokes.isEmpty else { return }
        pauseTimer = Timer.scheduledTimer(withTimeInterval: pauseDelay, repeats: false) { [weak self] _ in
            self?.onWritingPaused?()
        }
    }

    private func cancelPause() {
        pauseTimer?.invalidate()
        pauseTimer = nil
    }
}
