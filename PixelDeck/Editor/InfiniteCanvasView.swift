import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Ask the canvas to fit the art on screen (the nonce changes on each request).
struct FitCommand: Equatable {
    var nonce = 0
}

/// SwiftUI wrapper around the infinite canvas: one finger draws; two fingers pinch (changing how
/// big a pixel is on screen) and pan; a two-finger tap fits the art.
struct PixelCanvas: UIViewRepresentable {
    let state: CanvasState
    let model: EditorModel
    var fit = FitCommand()
    var drawingEnabled = true

    // Start from the current nonce so a recreated canvas doesn't replay the last fit.
    func makeCoordinator() -> Coordinator { Coordinator(model: model, lastFitNonce: fit.nonce) }

    func makeUIView(context: Context) -> InfiniteCanvasView {
        let view = InfiniteCanvasView()
        view.delegate = context.coordinator
        // A new view (e.g. after a layout switch or fold) picks up where the old one left off;
        // a sprite opened fresh is fitted on screen.
        view.setInitialViewport(model.viewport)
        return view
    }

    func updateUIView(_ view: InfiniteCanvasView, context: Context) {
        context.coordinator.model = model
        view.drawingEnabled = drawingEnabled
        view.render(state)
        if fit.nonce != context.coordinator.lastFitNonce {
            context.coordinator.lastFitNonce = fit.nonce
            view.fitToArt()
        }
    }

    final class Coordinator: InfiniteCanvasViewDelegate {
        var model: EditorModel
        var lastFitNonce: Int
        init(model: EditorModel, lastFitNonce: Int) {
            self.model = model
            self.lastFitNonce = lastFitNonce
        }

        func canvasTouchBegan(at p: Vec2) { model.touchBegan(at: p) }
        func canvasTouchMoved(to p: Vec2) { model.touchMoved(to: p) }
        func canvasTouchEnded() { model.touchEnded() }
        func canvasTouchCancelled() { model.touchCancelled() }
        func canvasViewportChanged(_ viewport: Viewport) { model.viewport = viewport }
        func canvasFitRect() -> PixelRect { model.contentBounds ?? PixelRect(x: -8, y: -8, width: 16, height: 16) }
    }
}

protocol InfiniteCanvasViewDelegate: AnyObject {
    func canvasTouchBegan(at p: Vec2)
    func canvasTouchMoved(to p: Vec2)
    func canvasTouchEnded()
    func canvasTouchCancelled()
    func canvasViewportChanged(_ viewport: Viewport)
    /// World rectangle to show when fitting (the art).
    func canvasFitRect() -> PixelRect
}

/// An endless checkerboard you can draw on. Positions are in world pixels; `viewport` says how
/// many points one pixel takes on screen and which world point is in the middle.
final class InfiniteCanvasView: UIView, UIGestureRecognizerDelegate {
    weak var delegate: InfiniteCanvasViewDelegate?
    var drawingEnabled = true {
        didSet { drawRecognizer.isEnabled = drawingEnabled }
    }

    private(set) var viewport = Viewport.initial
    private var needsInitialFit = false
    private var state: CanvasState?

    private let checkerLayer = CALayer()
    private let onionLayer = CALayer()
    private let imageLayer = CALayer()
    private let gridLayer = CAShapeLayer()
    private let mirrorLayer = CAShapeLayer()
    private let pathLayer = CAShapeLayer()
    private let selectionUnderLayer = CAShapeLayer()
    private let selectionLayer = CAShapeLayer()
    private var checkerCellPoints: CGFloat = 0

    private lazy var drawRecognizer = DrawGestureRecognizer(target: self, action: #selector(handleDraw(_:)))
    private lazy var pinchRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
    private lazy var panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    private lazy var fitTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleFitTap(_:)))

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.uiCheckA
        clipsToBounds = true
        isMultipleTouchEnabled = true

        for l in [checkerLayer, onionLayer, imageLayer] {
            l.magnificationFilter = .nearest
            l.minificationFilter = .nearest
            l.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
            layer.addSublayer(l)
        }
        gridLayer.fillColor = nil
        gridLayer.strokeColor = Theme.uiGrid.cgColor
        gridLayer.lineWidth = 1
        layer.addSublayer(gridLayer)

        mirrorLayer.fillColor = nil
        mirrorLayer.strokeColor = Theme.uiAccent2.withAlphaComponent(0.7).cgColor
        mirrorLayer.lineWidth = 2
        mirrorLayer.lineDashPattern = [6, 6]
        layer.addSublayer(mirrorLayer)

        pathLayer.fillColor = nil
        pathLayer.strokeColor = Theme.uiAccent.cgColor
        pathLayer.lineWidth = 2
        pathLayer.lineDashPattern = [2, 6]
        pathLayer.lineCap = .square
        layer.addSublayer(pathLayer)

        selectionUnderLayer.fillColor = nil
        selectionUnderLayer.strokeColor = Theme.uiInk.cgColor
        selectionUnderLayer.lineWidth = 2
        selectionLayer.fillColor = Theme.uiCream.withAlphaComponent(0.06).cgColor
        selectionLayer.strokeColor = Theme.uiCream.cgColor
        selectionLayer.lineWidth = 2
        selectionLayer.lineDashPattern = [5, 4]
        layer.addSublayer(selectionUnderLayer)
        layer.addSublayer(selectionLayer)

        panRecognizer.minimumNumberOfTouches = 2
        panRecognizer.maximumNumberOfTouches = 2
        fitTapRecognizer.numberOfTouchesRequired = 2
        for g in [drawRecognizer, pinchRecognizer, panRecognizer, fitTapRecognizer] as [UIGestureRecognizer] {
            g.delegate = self
            addGestureRecognizer(g)
        }

        isAccessibilityElement = true
        accessibilityTraits = .allowsDirectInteraction
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Viewport

    func setInitialViewport(_ v: Viewport?) {
        if let v { viewport = v } else { needsInitialFit = true }
    }

    private var s: CGFloat { CGFloat(viewport.pixelSize) }

    private func viewPoint(_ wx: Double, _ wy: Double) -> CGPoint {
        CGPoint(x: CGFloat(wx - viewport.centerX) * s + bounds.width / 2,
                y: CGFloat(wy - viewport.centerY) * s + bounds.height / 2)
    }

    private func worldPoint(_ p: CGPoint) -> Vec2 {
        Vec2(x: Double((p.x - bounds.width / 2) / s) + viewport.centerX,
             y: Double((p.y - bounds.height / 2) / s) + viewport.centerY)
    }

    private func viewRect(_ r: PixelRect) -> CGRect {
        let o = viewPoint(Double(r.x), Double(r.y))
        return CGRect(x: o.x, y: o.y, width: CGFloat(r.width) * s, height: CGFloat(r.height) * s)
    }

    /// Fits the art (or the area around the origin on a blank canvas) at the largest whole-point
    /// pixel size that leaves a margin.
    func fitToArt() {
        guard bounds.width > 0, bounds.height > 0 else { needsInitialFit = true; return }
        let r = delegate?.canvasFitRect() ?? state?.bounds ?? SpriteProject.initialBounds
        let fitW = (bounds.width - 32) / CGFloat(max(r.width, 1))
        let fitH = (bounds.height - 56) / CGFloat(max(r.height, 1))
        let size = min(max(floor(min(fitW, fitH)), Viewport.minPixelSize), 40)
        viewport = Viewport(pixelSize: Double(size), centerX: r.center.x, centerY: r.center.y)
        layoutLayers()
        report()
    }

    private func report() {
        delegate?.canvasViewportChanged(viewport)
    }

    // MARK: Rendering

    override func layoutSubviews() {
        super.layoutSubviews()
        if needsInitialFit, bounds.width > 0, state != nil {
            needsInitialFit = false
            fitToArt()
        }
        layoutLayers()
    }

    func render(_ new: CanvasState) {
        let old = state
        state = new
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if old?.grid != new.grid {
            imageLayer.contents = PixelRenderer.cgImage(new.grid)
        }
        if old?.onion != new.onion {
            onionLayer.contents = new.onion.flatMap { PixelRenderer.cgImage(PixelRenderer.tinted($0, with: Theme.onionRGBA)) }
        }
        onionLayer.opacity = Float(new.onionOpacity)
        CATransaction.commit()
        if needsInitialFit { setNeedsLayout() }
        layoutLayers()
    }

    private func layoutLayers() {
        guard let st = state, bounds.width > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let art = viewRect(st.bounds)
        imageLayer.frame = art
        onionLayer.frame = art
        layoutChecker()
        layoutGrid(show: st.showGrid)
        layoutOverlays(st)
        CATransaction.commit()
    }

    /// One checker cell per art pixel; when pixels are tiny, cells cover several pixels so the
    /// pattern stays readable.
    private func layoutChecker() {
        let cellWorld = max(1, Int((4 / s).rounded(.up)))
        let cell = CGFloat(cellWorld) * s
        if abs(cell - checkerCellPoints) > 0.001 {
            checkerCellPoints = cell
            let size = CGSize(width: cell * 2, height: cell * 2)
            let image = UIGraphicsImageRenderer(size: size).image { ctx in
                Theme.uiCheckA.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                Theme.uiCheckB.setFill()
                ctx.fill(CGRect(x: cell, y: 0, width: cell, height: cell))
                ctx.fill(CGRect(x: 0, y: cell, width: cell, height: cell))
            }
            checkerLayer.backgroundColor = UIColor(patternImage: image).cgColor
        }
        // Anchor the pattern to the world grid so it scrolls with the art.
        let topLeft = worldPoint(.zero)
        let period = Double(cellWorld * 2)
        let x0 = (topLeft.x / period).rounded(.down) * period
        let y0 = (topLeft.y / period).rounded(.down) * period
        let origin = viewPoint(x0, y0)
        checkerLayer.frame = CGRect(x: origin.x, y: origin.y,
                                    width: bounds.width - origin.x + cell * 2, height: bounds.height - origin.y + cell * 2)
    }

    /// Lines only for the visible part of the endless grid; hidden when pixels are too small.
    private func layoutGrid(show: Bool) {
        guard show, s >= 6 else { gridLayer.path = nil; return }
        let tl = worldPoint(.zero), br = worldPoint(CGPoint(x: bounds.width, y: bounds.height))
        let path = CGMutablePath()
        var x = tl.x.rounded(.down)
        while x <= br.x {
            let vx = viewPoint(x, 0).x.rounded() + 0.5
            path.move(to: CGPoint(x: vx, y: 0)); path.addLine(to: CGPoint(x: vx, y: bounds.height))
            x += 1
        }
        var y = tl.y.rounded(.down)
        while y <= br.y {
            let vy = viewPoint(0, y).y.rounded() + 0.5
            path.move(to: CGPoint(x: 0, y: vy)); path.addLine(to: CGPoint(x: bounds.width, y: vy))
            y += 1
        }
        gridLayer.path = path
    }

    private func layoutOverlays(_ st: CanvasState) {
        if st.mirror {
            let x = viewPoint(0, 0).x
            let p = CGMutablePath()
            p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: bounds.height))
            mirrorLayer.path = p
        } else {
            mirrorLayer.path = nil
        }

        if let r = st.selection {
            let path = CGPath(rect: viewRect(r), transform: nil)
            selectionLayer.path = path
            selectionUnderLayer.path = path
            if selectionLayer.animation(forKey: "ants") == nil {
                let ants = CABasicAnimation(keyPath: "lineDashPhase")
                ants.fromValue = 0
                ants.toValue = 9
                ants.duration = 0.6
                ants.repeatCount = .infinity
                selectionLayer.add(ants, forKey: "ants")
            }
        } else {
            selectionLayer.path = nil
            selectionUnderLayer.path = nil
            selectionLayer.removeAnimation(forKey: "ants")
        }

        if let points = st.motionPath, points.count > 1 {
            let p = CGMutablePath()
            p.addLines(between: points.map { viewPoint($0.x, $0.y) })
            pathLayer.path = p
        } else {
            pathLayer.path = nil
        }
    }

    // MARK: Gestures

    @objc private func handleDraw(_ g: DrawGestureRecognizer) {
        let p = worldPoint(g.location(in: self))
        switch g.state {
        case .began: delegate?.canvasTouchBegan(at: p)
        case .changed: delegate?.canvasTouchMoved(to: p)
        case .ended: delegate?.canvasTouchEnded()
        case .cancelled, .failed: delegate?.canvasTouchCancelled()
        default: break
        }
    }

    /// Zooms about the fingers: the world point under them stays put. Snaps to a whole number
    /// of points per pixel when the pinch ends, so pixels stay crisp.
    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        let loc = g.location(in: self)
        switch g.state {
        case .began, .changed:
            zoom(to: s * g.scale, about: loc)
            g.scale = 1
        case .ended, .cancelled:
            zoom(to: max(Viewport.minPixelSize, s.rounded()), about: loc)
        default:
            break
        }
    }

    private func zoom(to size: CGFloat, about loc: CGPoint) {
        let anchor = worldPoint(loc)
        let ns = min(max(size, CGFloat(Viewport.minPixelSize)), CGFloat(Viewport.maxPixelSize))
        viewport.pixelSize = Double(ns)
        viewport.centerX = anchor.x - Double((loc.x - bounds.width / 2) / ns)
        viewport.centerY = anchor.y - Double((loc.y - bounds.height / 2) / ns)
        layoutLayers()
        report()
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: self)
        g.setTranslation(.zero, in: self)
        viewport.centerX -= Double(t.x / s)
        viewport.centerY -= Double(t.y / s)
        layoutLayers()
        report()
    }

    @objc private func handleFitTap(_ g: UITapGestureRecognizer) {
        if g.state == .ended { fitToArt() }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

/// Starts the instant one finger lands, so single taps paint a pixel. When a second finger arrives
/// the stroke stops so the view can pinch/pan: within 0.25 s it's treated as the start of a pinch
/// and cancelled (the stray stroke is undone); later, the stroke so far is kept.
final class DrawGestureRecognizer: UIGestureRecognizer {
    private var tracked: UITouch?
    private var startTime: TimeInterval = 0
    private let handOffWindow: TimeInterval = 0.25

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if tracked == nil {
            let active = event.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled }.count ?? touches.count
            guard touches.count == 1, active <= 1, let t = touches.first else {
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
        if state == .began || state == .changed {
            state = quick ? .cancelled : .ended
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
