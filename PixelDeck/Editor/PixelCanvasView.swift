import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

enum ZoomAction: Equatable {
    case zoomIn, zoomOut, fit
}

struct ZoomCommand: Equatable {
    var action: ZoomAction = .fit
    var nonce = 0
}

/// SwiftUI wrapper around the UIKit canvas: one finger draws, two fingers pinch-zoom and pan.
struct PixelCanvas: UIViewRepresentable {
    let state: CanvasState
    let model: EditorModel
    let zoom: ZoomCommand

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> PixelCanvasView {
        let view = PixelCanvasView()
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: PixelCanvasView, context: Context) {
        context.coordinator.model = model
        view.render(state)
        if zoom.nonce != context.coordinator.lastZoomNonce {
            context.coordinator.lastZoomNonce = zoom.nonce
            view.perform(zoom.action)
        }
    }

    final class Coordinator: PixelCanvasViewDelegate {
        var model: EditorModel
        var lastZoomNonce = 0
        init(model: EditorModel) { self.model = model }

        func canvasTouchBegan(at p: Vec2) { model.touchBegan(at: p) }
        func canvasTouchMoved(to p: Vec2) { model.touchMoved(to: p) }
        func canvasTouchEnded() { model.touchEnded() }
        func canvasTouchCancelled() { model.touchCancelled() }
    }
}

protocol PixelCanvasViewDelegate: AnyObject {
    func canvasTouchBegan(at p: Vec2)
    func canvasTouchMoved(to p: Vec2)
    func canvasTouchEnded()
    func canvasTouchCancelled()
}

final class PixelCanvasView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    weak var delegate: PixelCanvasViewDelegate?

    private let scrollView = UIScrollView()
    private let board = UIView()
    private let checkerLayer = CALayer()
    private let onionLayer = CALayer()
    private let imageLayer = CALayer()
    private let gridLayer = CAShapeLayer()
    private let pathLayer = CAShapeLayer()
    private let selectionUnderLayer = CAShapeLayer()
    private let selectionLayer = CAShapeLayer()
    private lazy var drawRecognizer = DrawGestureRecognizer(target: self, action: #selector(handleDraw(_:)))

    private var state: CanvasState?
    private var pixelCount = 0
    private var boardSide: CGFloat = 0
    private var laidOutSize: CGSize = .zero

    private var cellSize: CGFloat { pixelCount > 0 ? boardSide / CGFloat(pixelCount) : 1 }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.delaysContentTouches = false
        scrollView.bouncesZoom = true
        scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
        scrollView.contentInsetAdjustmentBehavior = .never
        addSubview(scrollView)
        scrollView.addSubview(board)

        board.layer.shadowColor = UIColor.black.cgColor
        board.layer.shadowOpacity = 0.15
        board.layer.shadowRadius = 6
        board.layer.shadowOffset = CGSize(width: 0, height: 2)

        for layer in [checkerLayer, onionLayer, imageLayer] {
            layer.magnificationFilter = .nearest
            layer.minificationFilter = .nearest
            board.layer.addSublayer(layer)
        }

        gridLayer.fillColor = nil
        gridLayer.strokeColor = UIColor(white: 0.45, alpha: 0.35).cgColor
        board.layer.addSublayer(gridLayer)

        pathLayer.fillColor = nil
        pathLayer.strokeColor = UIColor.systemPink.cgColor
        pathLayer.lineCap = .round
        pathLayer.lineJoin = .round
        board.layer.addSublayer(pathLayer)

        selectionUnderLayer.fillColor = nil
        selectionUnderLayer.strokeColor = UIColor.white.cgColor
        selectionLayer.fillColor = UIColor.systemBlue.withAlphaComponent(0.08).cgColor
        selectionLayer.strokeColor = UIColor.black.cgColor
        board.layer.addSublayer(selectionUnderLayer)
        board.layer.addSublayer(selectionLayer)

        drawRecognizer.delegate = self
        board.addGestureRecognizer(drawRecognizer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        layoutBoard(force: false)
    }

    private func layoutBoard(force: Bool) {
        guard bounds.width > 0, bounds.height > 0, pixelCount > 0 else { return }
        guard force || bounds.size != laidOutSize else { return }
        laidOutSize = bounds.size

        let margin: CGFloat = 16
        // Whole points per pixel where possible, so the fitted canvas looks even.
        let available = max(1, min(bounds.width, bounds.height) - margin * 2)
        let perPixel = available / CGFloat(pixelCount)
        boardSide = perPixel >= 1 ? floor(perPixel) * CGFloat(pixelCount) : available

        scrollView.zoomScale = 1
        board.frame = CGRect(x: 0, y: 0, width: boardSide, height: boardSide)
        scrollView.contentSize = board.frame.size
        scrollView.minimumZoomScale = 0.5
        scrollView.maximumZoomScale = max(4, 64 / cellSize)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [checkerLayer, onionLayer, imageLayer, gridLayer, pathLayer, selectionUnderLayer, selectionLayer] {
            layer.frame = board.bounds
        }
        board.layer.shadowPath = UIBezierPath(rect: board.bounds).cgPath
        gridLayer.path = gridPath()
        updateOverlays()
        CATransaction.commit()
        centerBoard()
    }

    private func gridPath() -> CGPath {
        let path = CGMutablePath()
        let c = cellSize
        for i in 0...pixelCount {
            let p = CGFloat(i) * c
            path.move(to: CGPoint(x: p, y: 0)); path.addLine(to: CGPoint(x: p, y: boardSide))
            path.move(to: CGPoint(x: 0, y: p)); path.addLine(to: CGPoint(x: boardSide, y: p))
        }
        return path
    }

    private func centerBoard() {
        let w = board.frame.width, h = board.frame.height
        let x = max(0, (scrollView.bounds.width - w) / 2)
        let y = max(0, (scrollView.bounds.height - h) / 2)
        scrollView.contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
    }

    // MARK: Rendering

    func render(_ new: CanvasState) {
        let old = state
        state = new

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if new.size != pixelCount {
            pixelCount = new.size
            checkerLayer.contents = PixelRenderer.checkerboard(size: new.size)
            layoutBoard(force: true)
        }
        if old?.grid != new.grid || old?.size != new.size {
            imageLayer.contents = PixelRenderer.cgImage(new.grid)
        }
        if old?.onion != new.onion || old?.size != new.size {
            onionLayer.contents = new.onion.flatMap { PixelRenderer.cgImage($0) }
        }
        onionLayer.opacity = Float(new.onionOpacity)
        updateOverlays()
        CATransaction.commit()
    }

    /// Grid, selection outline and motion path. Line widths are divided by the zoom scale so they
    /// stay the same thickness on screen.
    private func updateOverlays() {
        let z = max(scrollView.zoomScale, 0.01)
        let c = cellSize

        gridLayer.lineWidth = 1 / z
        gridLayer.isHidden = !(state?.showGrid ?? true) || c * z < 4

        if let r = state?.selection {
            let rect = CGRect(x: CGFloat(r.x) * c, y: CGFloat(r.y) * c, width: CGFloat(r.width) * c, height: CGFloat(r.height) * c)
            let path = CGPath(rect: rect, transform: nil)
            selectionLayer.path = path
            selectionUnderLayer.path = path
            selectionLayer.lineWidth = 1.5 / z
            selectionUnderLayer.lineWidth = 1.5 / z
            selectionLayer.lineDashPattern = [NSNumber(value: Double(5 / z)), NSNumber(value: Double(4 / z))]
            selectionLayer.isHidden = false
            selectionUnderLayer.isHidden = false
            if selectionLayer.animation(forKey: "ants") == nil {
                let ants = CABasicAnimation(keyPath: "lineDashPhase")
                ants.fromValue = 0
                ants.toValue = 9 / z
                ants.duration = 0.6
                ants.repeatCount = .infinity
                selectionLayer.add(ants, forKey: "ants")
            }
        } else {
            selectionLayer.isHidden = true
            selectionUnderLayer.isHidden = true
            selectionLayer.removeAnimation(forKey: "ants")
        }

        if let points = state?.motionPath, points.count > 1 {
            let path = CGMutablePath()
            path.addLines(between: points.map { CGPoint(x: $0.x * c, y: $0.y * c) })
            pathLayer.path = path
            pathLayer.lineWidth = 2 / z
            pathLayer.lineDashPattern = [NSNumber(value: Double(1 / z)), NSNumber(value: Double(5 / z))]
            pathLayer.isHidden = false
        } else {
            pathLayer.isHidden = true
        }
    }

    func perform(_ action: ZoomAction) {
        switch action {
        case .zoomIn:
            scrollView.setZoomScale(min(scrollView.zoomScale * 2, scrollView.maximumZoomScale), animated: true)
        case .zoomOut:
            scrollView.setZoomScale(max(scrollView.zoomScale / 2, scrollView.minimumZoomScale), animated: true)
        case .fit:
            scrollView.setZoomScale(1, animated: true)
        }
    }

    // MARK: UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { board }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerBoard()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        selectionLayer.removeAnimation(forKey: "ants")
        updateOverlays()
        CATransaction.commit()
    }

    // MARK: Drawing input

    @objc private func handleDraw(_ g: DrawGestureRecognizer) {
        let loc = g.location(in: board)
        let p = Vec2(x: Double(loc.x / cellSize), y: Double(loc.y / cellSize))
        switch g.state {
        case .began: delegate?.canvasTouchBegan(at: p)
        case .changed: delegate?.canvasTouchMoved(to: p)
        case .ended: delegate?.canvasTouchEnded()
        case .cancelled, .failed: delegate?.canvasTouchCancelled()
        default: break
        }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

/// Starts the instant one finger lands, so single taps paint a pixel. If a second finger arrives
/// quickly, the touch is treated as the start of a pinch/pan and cancelled (the stroke is undone).
final class DrawGestureRecognizer: UIGestureRecognizer {
    private var tracked: UITouch?
    private var startTime: TimeInterval = 0
    private let handOffWindow: TimeInterval = 0.25

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if tracked == nil {
            guard touches.count == 1, let t = touches.first else {
                state = .failed
                return
            }
            tracked = t
            startTime = t.timestamp
            state = .began
            return
        }
        // Another finger joined.
        let quick = (touches.first?.timestamp ?? startTime) - startTime < handOffWindow
        if quick {
            state = .cancelled
        } else {
            for t in touches { ignore(t, for: event) }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let t = tracked, touches.contains(t), state == .began || state == .changed else { return }
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        guard let t = tracked, touches.contains(t) else { return }
        state = (state == .began || state == .changed) ? .ended : .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        state = (state == .began || state == .changed) ? .cancelled : .failed
    }

    override func reset() {
        super.reset()
        tracked = nil
    }
}
