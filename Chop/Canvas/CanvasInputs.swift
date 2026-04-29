import AppKit
import simd

/// Routes input events from the canvas to the active tool, and handles wheel
/// zoom (zoom-around-cursor) and the spacebar pan-tool override.
extension CanvasView {
    public override var acceptsFirstResponder: Bool { true }

    public override func mouseDown(with event: NSEvent) {
        updateCursorReadout(event: event)
        stopAutoscroll()
        toolContext().map { activeTool().mouseDown(event, ctx: $0) }
    }

    public override func mouseDragged(with event: NSEvent) {
        updateCursorReadout(event: event)
        toolContext().map { activeTool().mouseDragged(event, ctx: $0) }
        if activeTool().id == .rectSelect {
            updateAutoscroll(for: event)
        } else {
            stopAutoscroll()
        }
    }

    public override func mouseUp(with event: NSEvent) {
        updateCursorReadout(event: event)
        stopAutoscroll()
        toolContext().map { activeTool().mouseUp(event, ctx: $0) }
    }

    public override func mouseMoved(with event: NSEvent) {
        updateCursorReadout(event: event)
    }

    public override func mouseEntered(with event: NSEvent) {
        updateCursorReadout(event: event)
    }

    public override func mouseExited(with event: NSEvent) {
        infoPalette()?.updateCursor(image: nil)
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let opts: NSTrackingArea.Options = [
            .activeInKeyWindow,
            .mouseMoved,
            .mouseEnteredAndExited,
            .inVisibleRect,
        ]
        addTrackingArea(
            NSTrackingArea(rect: .zero, options: opts, owner: self, userInfo: nil)
        )
    }

    private func updateCursorReadout(event: NSEvent) {
        guard let doc = document, let info = infoPalette() else { return }
        let screen = canvasPoint(of: event)
        let viewport = viewportSize()
        let imagePt = CanvasMath.imageSpace(screen, view: doc.view, viewportSize: viewport)
        info.updateCursor(image: imagePt)
    }

    private func infoPalette() -> InfoPaletteView? {
        (window?.windowController as? ChopWindowController)?.info
    }

    public override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            spacebarPan = true
            invalidateCursor()
            return
        }
        // Bare-key shortcuts (no modifiers) for tools and view actions.
        let bareKey =
            event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
        if bareKey, let chars = event.charactersIgnoringModifiers,
            handleBareShortcut(chars)
        {
            return
        }
        toolContext().map { activeTool().keyDown(event, ctx: $0) }
    }

    private func handleBareShortcut(_ chars: String) -> Bool {
        let wc = window?.windowController as? ChopWindowController
        if let id = toolIdForShortcut(chars) {
            wc?.setActiveTool(id)
            return true
        }
        switch chars {
        case "f", "F":
            wc?.fitToWindow(nil)
            return true
        case "c", "C":
            wc?.centerImage(nil)
            return true
        default:
            return false
        }
    }

    private func toolIdForShortcut(_ chars: String) -> ToolId? {
        switch chars {
        case "1": return .pan
        case "2": return .zoom
        case "3": return .rectSelect
        default: return nil
        }
    }

    public override func keyUp(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            spacebarPan = false
            invalidateCursor()
        }
    }

    public override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: activeTool().cursor)
    }

    func invalidateCursor() {
        window?.invalidateCursorRects(for: self)
    }

    public override func scrollWheel(with event: NSEvent) {
        guard let doc = document else { return }
        let viewport = viewportSize()
        let cursor = canvasPoint(of: event)
        // Pinch / multi-touch trackpad gestures use magnification(); plain
        // scroll wheels and trackpad two-finger scroll arrive here.
        // scrollingDeltaY > 0 = scroll up / wheel forward → zoom in.
        let dy = Float(event.scrollingDeltaY) * (event.hasPreciseScrollingDeltas ? 0.01 : 0.1)
        let factor = expf(dy)
        let newZoom = CanvasMath.clampZoom(doc.view.zoom * factor)
        let newCenter = CanvasMath.centerForZoomAround(
            cursor: cursor,
            view: doc.view,
            viewportSize: viewport,
            newZoom: newZoom
        )
        doc.view.zoom = newZoom
        doc.view.center = newCenter
        documentDidChange()
        NotificationCenter.default.post(name: .chopViewDidChange, object: self)
    }

    public override func magnify(with event: NSEvent) {
        guard let doc = document else { return }
        let viewport = viewportSize()
        let cursor = canvasPoint(of: event)
        let factor = Float(1.0 + event.magnification)
        let newZoom = CanvasMath.clampZoom(doc.view.zoom * factor)
        let newCenter = CanvasMath.centerForZoomAround(
            cursor: cursor,
            view: doc.view,
            viewportSize: viewport,
            newZoom: newZoom
        )
        doc.view.zoom = newZoom
        doc.view.center = newCenter
        documentDidChange()
        NotificationCenter.default.post(name: .chopViewDidChange, object: self)
    }

    // MARK: - Spacebar panning override

    private static var kSpacebarKey: UInt8 = 0
    private(set) var spacebarPan: Bool {
        get { (objc_getAssociatedObject(self, &Self.kSpacebarKey) as? Bool) ?? false }
        set {
            objc_setAssociatedObject(self, &Self.kSpacebarKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    // MARK: - Helpers

    func toolContext() -> ToolContext? {
        guard let doc = document else { return nil }
        let wc = window?.windowController as? ChopWindowController
        return ToolContext(window: wc, canvas: self, document: doc)
    }

    func activeTool() -> any Tool {
        if spacebarPan { return ToolRegistry.shared.tool(for: .pan) }
        if let doc = document {
            return ToolRegistry.shared.tool(for: doc.activeToolId)
        }
        return ToolRegistry.shared.tool(for: .pan)
    }

    func canvasPoint(of event: NSEvent) -> SIMD2<Float> {
        let p = convert(event.locationInWindow, from: nil)
        let backing = convertToBacking(p)
        let drawable = drawableSize
        return SIMD2<Float>(Float(backing.x), Float(drawable.height - backing.y))
    }

    func viewportSize() -> SIMD2<Float> {
        let s = drawableSize
        return SIMD2<Float>(Float(s.width), Float(s.height))
    }
}

extension Notification.Name {
    static let chopViewDidChange = Notification.Name("ChopViewDidChange")
}
