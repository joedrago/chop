import AppKit
import Metal
import simd

/// Owns the document window and its canvas + chrome (PLAN.md §3, §6).
@MainActor
final class ChopWindowController: NSWindowController, NSWindowDelegate {
    let canvas: CanvasView
    let toolbox: ToolboxView
    let info: InfoPaletteView
    let statusBar: StatusBarView
    private let scrollerH: NSScroller
    private let scrollerV: NSScroller
    private var viewObserver: NSObjectProtocol?
    private let toolbar = ChopToolbar()
    private var lastKnownDimensions: (Int, Int)?

    /// UserDefaults key for the persisted document-window frame. We bypass
    /// NSWindow.setFrameAutosaveName because in our setup it wasn't reliably
    /// saving on `windowDidMove`/Resize. Manual save in the delegate methods
    /// below — same effect, no surprises.
    private static let savedFrameKey = "ChopDocumentWindowFrame"

    init(document: ChopDocument) {
        chopLog("ChopWindowController init begin")
        let initialFrame = NSRect(x: 0, y: 0, width: 980, height: 720)
        let style: NSWindow.StyleMask = [
            .titled, .closable, .miniaturizable, .resizable,
        ]
        let window = NSWindow(
            contentRect: initialFrame,
            styleMask: style,
            backing: .buffered,
            defer: true
        )
        window.tabbingMode = .preferred

        // Restore saved frame if we have one; otherwise center on screen.
        if let savedFrame = ChopWindowController.loadSavedFrame() {
            chopLog("loaded saved frame=\(savedFrame)")
            window.setFrame(savedFrame, display: false)
        } else {
            chopLog("no saved frame; centering")
            window.center()
        }
        window.title = document.displayName ?? "Untitled"

        canvas = CanvasView(frame: .zero, device: nil)
        canvas.translatesAutoresizingMaskIntoConstraints = false
        toolbox = ToolboxView(frame: .zero)
        toolbox.translatesAutoresizingMaskIntoConstraints = false
        info = InfoPaletteView(frame: .zero)
        info.translatesAutoresizingMaskIntoConstraints = false
        statusBar = StatusBarView(frame: .zero)
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        scrollerH = NSScroller(frame: .zero)
        scrollerH.translatesAutoresizingMaskIntoConstraints = false
        scrollerH.scrollerStyle = .legacy
        scrollerH.controlSize = .regular
        scrollerH.knobStyle = .default
        scrollerV = NSScroller(frame: .zero)
        scrollerV.translatesAutoresizingMaskIntoConstraints = false
        scrollerV.scrollerStyle = .legacy
        scrollerV.controlSize = .regular
        scrollerV.knobStyle = .default

        let content = NSView(frame: initialFrame)
        content.addSubview(toolbox)
        content.addSubview(info)
        content.addSubview(canvas)
        content.addSubview(scrollerH)
        content.addSubview(scrollerV)
        content.addSubview(statusBar)

        let toolboxWidth: CGFloat = 36
        let infoWidth: CGFloat = 200
        let scrollerThickness: CGFloat = 15
        let statusHeight: CGFloat = 22

        NSLayoutConstraint.activate([
            // Toolbox — left edge full height (above status bar).
            toolbox.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            toolbox.topAnchor.constraint(equalTo: content.topAnchor),
            toolbox.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            toolbox.widthAnchor.constraint(equalToConstant: toolboxWidth),

            // Info — right edge full height.
            info.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            info.topAnchor.constraint(equalTo: content.topAnchor),
            info.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            info.widthAnchor.constraint(equalToConstant: infoWidth),

            // Canvas — central area. Leaves room for scrollers on right & bottom.
            canvas.leadingAnchor.constraint(equalTo: toolbox.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: content.topAnchor),
            canvas.trailingAnchor.constraint(equalTo: scrollerV.leadingAnchor),
            canvas.bottomAnchor.constraint(equalTo: scrollerH.topAnchor),

            // Vertical scroller — between canvas and info.
            scrollerV.topAnchor.constraint(equalTo: content.topAnchor),
            scrollerV.bottomAnchor.constraint(equalTo: scrollerH.topAnchor),
            scrollerV.trailingAnchor.constraint(equalTo: info.leadingAnchor),
            scrollerV.widthAnchor.constraint(equalToConstant: scrollerThickness),

            // Horizontal scroller — bottom of canvas area, left of corner.
            scrollerH.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            scrollerH.trailingAnchor.constraint(equalTo: scrollerV.leadingAnchor),
            scrollerH.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            scrollerH.heightAnchor.constraint(equalToConstant: scrollerThickness),

            // Status bar — full width along the bottom.
            statusBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: statusHeight),
        ])

        window.contentView = content
        super.init(window: window)
        // NOTE: do NOT assign `self.document = document` here. The NSDocument
        // wires up `controller.document` itself when `addWindowController(_:)`
        // is called from `ChopDocument.makeWindowControllers()` — assigning
        // it manually here causes the controller to be added then removed
        // during `addWindowController`, leaving `windowControllers` empty.
        window.delegate = self

        canvas.document = document.model
        toolbox.document = document.model
        statusBar.document = document.model
        info.document = document.model
        toolbox.refresh()
        statusBar.refresh()
        info.refresh()
        toolbox.onToolChanged = { [weak self] _ in
            self?.canvas.documentDidChange()
            self?.canvas.invalidateCursor()
        }
        // Queue a fit-to-window. The canvas itself performs it once Auto Layout
        // has given it a real drawableSize.
        canvas.requestFitToWindow()
        if let model = document.model {
            lastKnownDimensions = (model.width, model.height)
        }

        toolbar.windowController = self
        toolbar.install(on: window)

        scrollerH.target = self
        scrollerH.action = #selector(horizontalScrollerChanged(_:))
        scrollerV.target = self
        scrollerV.action = #selector(verticalScrollerChanged(_:))

        viewObserver = NotificationCenter.default.addObserver(
            forName: .chopViewDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshChrome() }
        }
        chopLog("ChopWindowController init done")
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        chopLog("windowDidLoad")
    }

    override func showWindow(_ sender: Any?) {
        chopLog(
            "showWindow called; hasWindow=\(self.window != nil) "
                + "frame=\(String(describing: self.window?.frame))"
        )
        super.showWindow(sender)
        chopLog(
            "showWindow returned; isVisible=\(self.window?.isVisible ?? false) "
                + "isKey=\(self.window?.isKeyWindow ?? false)"
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used; programmatic only.")
    }

    deinit {
        if let obs = viewObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    func documentDidUpdate() {
        canvas.documentDidChange()
        canvas.selectionDidChange()
        // If the document's dimensions changed (Crop, Resize, undo/redo of
        // either), re-fit so the new image fills the canvas instead of being
        // off-center or zoomed to the old size.
        if let model = (document as? ChopDocument)?.model {
            let dims = (model.width, model.height)
            if let prev = lastKnownDimensions, prev != dims {
                canvas.requestFitToWindow()
            }
            lastKnownDimensions = dims
        }
        refreshChrome()
    }

    func refreshChrome() {
        statusBar.refresh()
        toolbox.refresh()
        info.refresh()
        updateScrollers()
    }

    // MARK: - Scrollers

    private func updateScrollers() {
        guard let model = (document as? ChopDocument)?.model else { return }
        let viewportPixels = canvas.drawableSize  // backing pixels
        let imgW = Float(model.width)
        let imgH = Float(model.height)
        let zoom = max(model.view.zoom, 0.0001)
        // Visible region in image space.
        let visW = Float(viewportPixels.width) / zoom
        let visH = Float(viewportPixels.height) / zoom

        configure(scroller: scrollerH, image: imgW, visible: visW, center: model.view.center.x)
        configure(scroller: scrollerV, image: imgH, visible: visH, center: model.view.center.y)
    }

    private func configure(scroller: NSScroller, image: Float, visible: Float, center: Float) {
        if visible >= image {
            scroller.knobProportion = 1.0
            scroller.doubleValue = 0.5
            scroller.isEnabled = false
            return
        }
        scroller.isEnabled = true
        scroller.knobProportion = CGFloat(visible / image)
        // Map center to [0, 1] over the range [visible/2, image - visible/2].
        let halfVis = visible * 0.5
        let denom = max(image - visible, 1e-3)
        let t = (center - halfVis) / denom
        scroller.doubleValue = Double(min(max(t, 0), 1))
    }

    @objc private func horizontalScrollerChanged(_ sender: NSScroller) {
        guard let model = (document as? ChopDocument)?.model else { return }
        scrollerDidChange(sender, axis: .horizontal, model: model)
    }

    @objc private func verticalScrollerChanged(_ sender: NSScroller) {
        guard let model = (document as? ChopDocument)?.model else { return }
        scrollerDidChange(sender, axis: .vertical, model: model)
    }

    private enum Axis { case horizontal, vertical }

    private func scrollerDidChange(_ scroller: NSScroller, axis: Axis, model: Document) {
        let viewportPixels = canvas.drawableSize
        let zoom = max(model.view.zoom, 0.0001)
        let imageSize: Float = axis == .horizontal ? Float(model.width) : Float(model.height)
        let visible: Float =
            axis == .horizontal
            ? Float(viewportPixels.width) / zoom
            : Float(viewportPixels.height) / zoom

        let halfVis = visible * 0.5
        let denom = max(imageSize - visible, 1e-3)

        let pageStep: Float = visible * 0.9
        let lineStep: Float = max(visible * 0.05, 1)

        let part = scroller.hitPart
        var newCenter: Float =
            axis == .horizontal ? model.view.center.x : model.view.center.y

        switch part {
        case .knobSlot, .knob:
            newCenter = halfVis + Float(scroller.doubleValue) * denom
        case .decrementPage:
            newCenter -= pageStep
        case .incrementPage:
            newCenter += pageStep
        case .decrementLine:
            newCenter -= lineStep
        case .incrementLine:
            newCenter += lineStep
        default:
            break
        }
        let lo = halfVis
        let hi = imageSize - halfVis
        newCenter = max(lo, min(hi, newCenter))
        if axis == .horizontal {
            model.view.center.x = newCenter
        } else {
            model.view.center.y = newCenter
        }
        canvas.documentDidChange()
        refreshChrome()
    }

    // MARK: - Tools menu actions

    @objc func selectToolRect(_ sender: Any?) { setActiveTool(.rectSelect) }
    @objc func selectToolPan(_ sender: Any?) { setActiveTool(.pan) }
    @objc func selectToolZoom(_ sender: Any?) { setActiveTool(.zoom) }

    func setActiveTool(_ id: ToolId) {
        guard let model = (document as? ChopDocument)?.model else { return }
        model.activeToolId = id
        toolbox.refresh()
        canvas.documentDidChange()
        canvas.invalidateCursor()
    }

    // MARK: - View menu actions

    @objc func zoomIn(_ sender: Any?) { applyZoomFactor(2.0) }
    @objc func zoomOut(_ sender: Any?) { applyZoomFactor(0.5) }
    @objc func actualSize(_ sender: Any?) {
        guard let model = (document as? ChopDocument)?.model else { return }
        applyZoom(to: 1.0, around: viewportCenterScreen(), model: model)
    }
    @objc func fitToWindow(_ sender: Any?) {
        // Re-use the same code path as the initial fit so we get correct
        // behaviour even if drawableSize is briefly zero.
        canvas.requestFitToWindow()
    }

    @objc func centerImage(_ sender: Any?) {
        guard let model = (document as? ChopDocument)?.model else { return }
        let imageSize = SIMD2<Float>(Float(model.width), Float(model.height))
        model.view.center = imageSize * 0.5
        canvas.documentDidChange()
        NotificationCenter.default.post(name: .chopViewDidChange, object: canvas)
    }

    private func applyZoomFactor(_ factor: Float) {
        guard let model = (document as? ChopDocument)?.model else { return }
        let newZoom = CanvasMath.clampZoom(model.view.zoom * factor)
        applyZoom(to: newZoom, around: viewportCenterScreen(), model: model)
    }

    private func applyZoom(to newZoom: Float, around screen: SIMD2<Float>, model: Document) {
        let canvasSize = canvas.drawableSize
        let viewport = SIMD2<Float>(Float(canvasSize.width), Float(canvasSize.height))
        let newCenter = CanvasMath.centerForZoomAround(
            cursor: screen,
            view: model.view,
            viewportSize: viewport,
            newZoom: newZoom
        )
        model.view.zoom = newZoom
        model.view.center = newCenter
        canvas.documentDidChange()
        refreshChrome()
    }

    private func viewportCenterScreen() -> SIMD2<Float> {
        let s = canvas.drawableSize
        return SIMD2<Float>(Float(s.width) * 0.5, Float(s.height) * 0.5)
    }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        canvas.documentDidChange()
        refreshChrome()
        saveCurrentFrame()
    }

    func windowDidMove(_ notification: Notification) {
        saveCurrentFrame()
    }

    // MARK: - Frame persistence

    private func saveCurrentFrame() {
        guard let frame = window?.frame else { return }
        let str = NSStringFromRect(frame)
        UserDefaults.standard.set(str, forKey: Self.savedFrameKey)
    }

    fileprivate static func loadSavedFrame() -> NSRect? {
        guard
            let str = UserDefaults.standard.string(forKey: savedFrameKey)
        else {
            return nil
        }
        let r = NSRectFromString(str)
        // Sanity: reject empty or tiny rects (corrupt prefs).
        if r.size.width < 100 || r.size.height < 100 { return nil }
        // Make sure the saved frame intersects at least one currently-attached
        // screen. Otherwise the window would land off-screen on a removed display.
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(r) }
        return onScreen ? r : nil
    }
}
