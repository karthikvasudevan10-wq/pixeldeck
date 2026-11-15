import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Ask the canvas to fit the art on screen (the nonce changes on each request).
struct FitCommand: Equatable {
    enum Action: Equatable { case fit, zoomIn, zoomOut }
    var action: Action = .fit
    var nonce = 0
}

/// What Apple Pencil's double-tap or squeeze asks for (following the user's Pencil settings).
enum PencilAction { case toggleEraser, previousTool, showColorPicker }

/// SwiftUI wrapper around the infinite canvas: one finger draws; two fingers pinch (changing how
/// big a pixel is on screen) and pan; a two-finger tap fits the art.
struct PixelCanvas: UIViewRepresentable {
    let state: CanvasState
    let model: EditorModel
    var fit = FitCommand()
    var drawingEnabled = true
    /// Apple Pencil draws; fingers only pan and zoom (palm rejection).
    var pencilOnly = false
    var onPencilDetected: () -> Void = {}
    var onPencilAction: (PencilAction) -> Void = { _ in }

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
        context.coordinator.onPencilDetected = onPencilDetected
        context.coordinator.onPencilAction = onPencilAction
        view.drawingEnabled = drawingEnabled
        view.pencilOnly = pencilOnly
        view.render(state)
        if fit.nonce != context.coordinator.lastFitNonce {
            context.coordinator.lastFitNonce = fit.nonce
            view.perform(fit.action)
        }
    }

    final class Coordinator: InfiniteCanvasViewDelegate {
        var model: EditorModel
        var lastFitNonce: Int
        var onPencilDetected: () -> Void = {}
        var onPencilAction: (PencilAction) -> Void = { _ in }
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
        func canvasPencilDetected() { onPencilDetected() }
        func canvasPencilAction(_ action: PencilAction) { onPencilAction(action) }
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
    /// An Apple Pencil touched the canvas.
    func canvasPencilDetected()
    func canvasPencilAction(_ action: PencilAction)
}

/// An endless checkerboard you can draw on. Positions are in world pixels; `viewport` says how
/// many points one pixel takes on screen and which world point is in the middle.
final class InfiniteCanvasView: UIView, UIGestureRecognizerDelegate, UIPencilInteractionDelegate {
    weak var delegate: InfiniteCanvasViewDelegate?
    var drawingEnabled = true {
        didSet { drawRecognizer.isEnabled = drawingEnabled }
    }
    /// Pencil draws; one finger pans, two pinch. Turned on automatically the first time a Pencil
    /// is used (in the Studio), and switchable in the sprite menu.
    var pencilOnly = false {
        didSet {
            guard pencilOnly != oldValue else { return }
            drawRecognizer.pencilOnly = pencilOnly
            panRecognizer.minimumNumberOfTouches = pencilOnly ? 1 : 2
        }
    }
    /// The pixel under a hovering Apple Pencil or pointer.
    private var hoverPixel: PixelPoint?

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
    /// What the grid path was last built for; it's rebuilt only when this changes.
    private var gridKey: (Viewport, CGSize, Bool)?
    /// Where the fingers were on the last pinch update (at .ended one has already lifted).
    private var lastPinchLocation: CGPoint = .zero
    /// When the view was last pinched or panned, so a two-finger pinch isn't also a fit tap.
    private var lastTransformTime: CFTimeInterval = 0

    private lazy var drawRecognizer = DrawGestureRecognizer(target: self, action: #selector(handleDraw(_:)))
    private lazy var pinchRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
    private lazy var panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    private lazy var fitTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleFitTap(_:)))
    /// Trackpad two-finger scrolling and mouse wheels: pan the canvas.
    private lazy var scrollRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    /// Apple Pencil hover (M2 iPads and later) and pointer hover: preview the pixel.
    private lazy var hoverRecognizer = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
    private let hoverLayer = CAShapeLayer()
    private let hoverUnderLayer = CAShapeLayer()

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
        gridLayer.lineWidth = 1
        layer.addSublayer(gridLayer)

        mirrorLayer.fillColor = nil
        mirrorLayer.lineWidth = 2
        mirrorLayer.lineDashPattern = [6, 6]
        layer.addSublayer(mirrorLayer)

        pathLayer.fillColor = nil
        pathLayer.lineWidth = 2
        pathLayer.lineDashPattern = [2, 6]
        pathLayer.lineCap = .square
        layer.addSublayer(pathLayer)

        selectionUnderLayer.fillColor = nil
        selectionUnderLayer.lineWidth = 2
        selectionLayer.lineWidth = 2
        selectionLayer.lineDashPattern = [5, 4]
        layer.addSublayer(selectionUnderLayer)
        layer.addSublayer(selectionLayer)

        let fingers = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        panRecognizer.minimumNumberOfTouches = 2
        panRecognizer.maximumNumberOfTouches = 2
        panRecognizer.allowedTouchTypes = fingers          // the Pencil and mouse never pan
        fitTapRecognizer.numberOfTouchesRequired = 2
        fitTapRecognizer.allowedTouchTypes = fingers
        scrollRecognizer.allowedScrollTypesMask = .all
        scrollRecognizer.allowedTouchTypes = []            // scroll events only, no touches
        drawRecognizer.onPencil = { [weak self] in self?.delegate?.canvasPencilDetected() }
        for g in [drawRecognizer, pinchRecognizer, panRecognizer, fitTapRecognizer, scrollRecognizer, hoverRecognizer] as [UIGestureRecognizer] {
            g.delegate = self
            addGestureRecognizer(g)
        }

        hoverUnderLayer.fillColor = nil
        hoverUnderLayer.lineWidth = 3
        hoverLayer.fillColor = nil
        hoverLayer.lineWidth = 1.5
        layer.addSublayer(hoverUnderLayer)
        layer.addSublayer(hoverLayer)

        let pencil = UIPencilInteraction()
        pencil.delegate = self
        addInteraction(pencil)

        // Layer colours are fixed CGColors, so re-apply them when Light/Dark changes.
        applyColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: InfiniteCanvasView, _: UITraitCollection) in
            view.applyColors()
        }

        isAccessibilityElement = true
        accessibilityTraits = .allowsDirectInteraction
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Resolves the theme's light/dark colours for the layers (and redraws the checker pattern).
    private func applyColors() {
        let t = traitCollection
        func c(_ u: UIColor, alpha: CGFloat = 1) -> CGColor { u.resolvedColor(with: t).withAlphaComponent(alpha).cgColor }
        gridLayer.strokeColor = c(Theme.uiGrid)
        mirrorLayer.strokeColor = c(Theme.uiAccent2, alpha: 0.7)
        pathLayer.strokeColor = c(Theme.uiAccent)
        selectionUnderLayer.strokeColor = c(Theme.uiInk)
        selectionLayer.fillColor = c(Theme.uiCream, alpha: 0.06)
        selectionLayer.strokeColor = c(Theme.uiCream)
        hoverUnderLayer.strokeColor = c(Theme.uiInk)
        hoverLayer.strokeColor = c(Theme.uiCream)
        checkerCellPoints = 0                      // forces the pattern to be redrawn
        layoutLayers()
    }

    /// Folding or unfolding an iPhone Duo (or rotating) can swap the Studio's layout mid-stroke,
    /// which removes this view. Finish the stroke rather than letting the touch be cancelled,
    /// which would undo it.
    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil, drawRecognizer.isTracking {
            drawRecognizer.finishedByRemoval = true
            for p in drawRecognizer.drainSamples() { delegate?.canvasTouchMoved(to: worldPoint(p)) }
            delegate?.canvasTouchEnded()
        }
    }

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
    func perform(_ action: FitCommand.Action) {
        let centre = CGPoint(x: bounds.midX, y: bounds.midY)
        switch action {
        case .fit: fitToArt()
        case .zoomIn: zoom(to: (s * 2).rounded(), about: centre)
        case .zoomOut: zoom(to: max(1, (s / 2).rounded()), about: centre)
        }
    }

    func fitToArt() {
        guard bounds.width > 0, bounds.height > 0 else { needsInitialFit = true; return }
        let r = delegate?.canvasFitRect() ?? state?.bounds ?? SpriteProject.initialBounds
        let fitW = (bounds.width - 32) / CGFloat(max(r.width, 1))
        let fitH = (bounds.height - 56) / CGFloat(max(r.height, 1))
        let size = min(max(floor(min(fitW, fitH)), CGFloat(Viewport.minPixelSize)), 40)
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
        // Versions, not pixel comparisons: this runs on every touch.
        if old?.gridVersion != new.gridVersion {
            imageLayer.contents = PixelRenderer.cgImage(new.grid)
        }
        if old?.onionVersion != new.onionVersion {
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
                Theme.uiCheckA.resolvedColor(with: traitCollection).setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                Theme.uiCheckB.resolvedColor(with: traitCollection).setFill()
                ctx.fill(CGRect(x: cell, y: 0, width: cell, height: cell))
                ctx.fill(CGRect(x: 0, y: cell, width: cell, height: cell))
            }
            checkerLayer.backgroundColor = UIColor(patternImage: image).cgColor
        }
        // Anchor the pattern to the world grid so it scrolls with the art.
        let topLeft = worldPoint(.zero)
        let worldPeriod = Double(cellWorld * 2)
        let x0 = (topLeft.x / worldPeriod).rounded(.down) * worldPeriod
        let y0 = (topLeft.y / worldPeriod).rounded(.down) * worldPeriod
        let origin = viewPoint(x0, y0)
        // Whole pattern periods, so the (flipped) pattern's phase can't drift vertically.
        let period = cell * 2
        let w = ((bounds.width - origin.x) / period).rounded(.up) * period + period
        let h = ((bounds.height - origin.y) / period).rounded(.up) * period + period
        checkerLayer.frame = CGRect(x: origin.x, y: origin.y, width: w, height: h)
    }

    /// Lines only for the visible part of the endless grid; hidden when pixels are too small.
    private func layoutGrid(show: Bool) {
        // Drawing doesn't move the grid, so don't rebuild it on every stroke.
        if let k = gridKey, k.0 == viewport, k.1 == bounds.size, k.2 == show { return }
        gridKey = (viewport, bounds.size, show)
        guard show, s >= 6 else { gridLayer.path = nil; return }
        let tl = worldPoint(.zero), br = worldPoint(CGPoint(x: bounds.width, y: bounds.height))
        gridLayer.lineWidth = 1 / max(traitCollection.displayScale, 1)
        let path = CGMutablePath()
        var x = tl.x.rounded(.down)
        while x <= br.x {
            let vx = viewPoint(x, 0).x
            path.move(to: CGPoint(x: vx, y: 0)); path.addLine(to: CGPoint(x: vx, y: bounds.height))
            x += 1
        }
        var y = tl.y.rounded(.down)
        while y <= br.y {
            let vy = viewPoint(0, y).y
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

        if let h = hoverPixel, drawingEnabled {
            let path = CGPath(rect: viewRect(PixelRect(x: h.x, y: h.y, width: 1, height: 1)), transform: nil)
            hoverLayer.path = path
            hoverUnderLayer.path = path
        } else {
            hoverLayer.path = nil
            hoverUnderLayer.path = nil
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
        // Already finished when the view was removed (see willMove(toWindow:)).
        if g.finishedByRemoval { return }
        switch g.state {
        case .began:
            hoverPixel = nil
            let samples = g.drainSamples()
            delegate?.canvasTouchBegan(at: worldPoint(samples.first ?? g.location(in: self)))
            for p in samples.dropFirst() { delegate?.canvasTouchMoved(to: worldPoint(p)) }
        case .changed:
            // Every sample since the last update (Apple Pencil reports up to 240 a second), so
            // fast curves keep their shape.
            for p in g.drainSamples() { delegate?.canvasTouchMoved(to: worldPoint(p)) }
        case .ended:
            for p in g.drainSamples() { delegate?.canvasTouchMoved(to: worldPoint(p)) }
            delegate?.canvasTouchEnded()
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
            lastPinchLocation = loc
            lastTransformTime = CACurrentMediaTime()
            zoom(to: s * g.scale, about: loc)
            g.scale = 1
        case .ended, .cancelled:
            zoom(to: max(CGFloat(Viewport.minPixelSize), s.rounded()), about: lastPinchLocation)
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
        if t != .zero { lastTransformTime = CACurrentMediaTime() }
        viewport.centerX -= Double(t.x / s)
        viewport.centerY -= Double(t.y / s)
        layoutLayers()
        report()
    }

    @objc private func handleHover(_ g: UIHoverGestureRecognizer) {
        switch g.state {
        case .began, .changed: hoverPixel = worldPoint(g.location(in: self)).pixel
        default: hoverPixel = nil
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let st = state { layoutOverlays(st) }
        CATransaction.commit()
    }

    // MARK: Apple Pencil double-tap and squeeze

    /// iPadOS before 17.5.
    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        perform(pencil: UIPencilInteraction.preferredTapAction)
    }

    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        perform(pencil: UIPencilInteraction.preferredTapAction)
    }

    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        if squeeze.phase == .ended { perform(pencil: UIPencilInteraction.preferredSqueezeAction) }
    }

    /// Follows the user's choice in Settings › Apple Pencil.
    private func perform(pencil action: UIPencilPreferredAction) {
        if #available(iOS 17.5, *), action == .runSystemShortcut { return }   // the system handles it
        switch action {
        case .ignore: break
        case .switchEraser: delegate?.canvasPencilAction(.toggleEraser)
        case .switchPrevious: delegate?.canvasPencilAction(.previousTool)
        default: delegate?.canvasPencilAction(.showColorPicker)            // colour / contextual palette
        }
    }

    @objc private func handleFitTap(_ g: UITapGestureRecognizer) {
        if g.state == .ended, CACurrentMediaTime() - lastTransformTime > 0.4 { fitToArt() }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

/// Starts the instant a finger or Pencil lands, so single taps paint a pixel. When a second finger
/// arrives the stroke stops so the view can pinch/pan: within 0.25 s it's treated as the start of a
/// pinch and cancelled (the stray stroke is undone); later, the stroke so far is kept.
///
/// With `pencilOnly`, fingers are ignored (they pan and zoom instead), and nothing interrupts a
/// Pencil stroke — a resting palm can't draw or cut it short.
final class DrawGestureRecognizer: UIGestureRecognizer {
    var pencilOnly = false
    /// Called when an Apple Pencil touches the view.
    var onPencil: (() -> Void)?
    private var tracked: UITouch?
    private var startTime: TimeInterval = 0
    private let handOffWindow: TimeInterval = 0.25
    var isTracking: Bool { tracked != nil && (state == .began || state == .changed) }
    /// Set when the stroke was finished because the view left the screen.
    var finishedByRemoval = false
    /// Locations since the last update, in the view's coordinates, including coalesced samples.
    private var samples: [CGPoint] = []

    func drainSamples() -> [CGPoint] {
        defer { samples.removeAll(keepingCapacity: true) }
        return samples
    }

    private func isFinger(_ t: UITouch) -> Bool { t.type == .direct }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if touches.contains(where: { $0.type == .pencil }) { onPencil?() }

        if tracked == nil {
            if pencilOnly {
                for t in touches where isFinger(t) { ignore(t, for: event) }
            }
            let candidates = touches.filter { !(pencilOnly && isFinger($0)) }
            guard !candidates.isEmpty else { return }
            // Only touches on the canvas count (a thumb resting on the dock mustn't block drawing).
            let active = event.allTouches?.filter {
                $0.view === view && $0.phase != .ended && $0.phase != .cancelled && !(pencilOnly && isFinger($0))
            }.count ?? candidates.count
            guard candidates.count == 1, active <= 1, let t = candidates.first else {
                state = .failed
                return
            }
            tracked = t
            startTime = t.timestamp
            samples = [t.location(in: view)]
            state = .began
            return
        }

        // Another touch joined. A Pencil stroke carries on regardless (palm rejection).
        if pencilOnly || tracked?.type == .pencil {
            for t in touches where t !== tracked { ignore(t, for: event) }
            return
        }
        let quick = (touches.first?.timestamp ?? startTime) - startTime < handOffWindow
        if state == .began || state == .changed {
            state = quick ? .cancelled : .ended
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let t = tracked, touches.contains(t), state == .began || state == .changed else { return }
        let coalesced = event.coalescedTouches(for: t) ?? [t]
        samples.append(contentsOf: coalesced.map { $0.location(in: view) })
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        guard let t = tracked, touches.contains(t) else { return }
        state = (state == .began || state == .changed) ? .ended : .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        guard let t = tracked, touches.contains(t) else { return }
        state = (state == .began || state == .changed) ? .cancelled : .failed
    }

    override func reset() {
        super.reset()
        tracked = nil
        finishedByRemoval = false
        samples.removeAll(keepingCapacity: true)
    }
}
