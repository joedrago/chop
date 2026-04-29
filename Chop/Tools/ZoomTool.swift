import AppKit
import simd

/// Drag-vertically = continuous zoom anchored at the click point
/// A simple click zooms in by 2× (option-click zooms out).
@MainActor
final class ZoomTool: Tool {
    let id: ToolId = .zoom
    let displayName: String = "Zoom"
    let cursor: NSCursor = .crosshair

    private var anchorImage: SIMD2<Float> = .zero
    private var anchorScreen: SIMD2<Float> = .zero
    private var startZoom: Float = 1.0
    private var dragging: Bool = false
    private var didDrag: Bool = false

    func mouseDown(_ event: NSEvent, ctx: ToolContext) {
        dragging = true
        didDrag = false
        startZoom = ctx.document.view.zoom
        let screen = canvasPoint(event, in: ctx)
        anchorScreen = screen
        let viewport = viewportSize(ctx)
        anchorImage = CanvasMath.imageSpace(
            screen,
            view: ctx.document.view,
            viewportSize: viewport
        )
    }

    func mouseDragged(_ event: NSEvent, ctx: ToolContext) {
        guard dragging else { return }
        didDrag = true
        // ~1% per pixel vertically, downward = zoom in.
        let dy = Float(event.deltaY)
        let factor = expf(-dy * 0.01)
        applyZoom(by: factor, around: anchorScreen, ctx: ctx)
    }

    func mouseUp(_ event: NSEvent, ctx: ToolContext) {
        defer { dragging = false }
        if !didDrag {
            // Click = 2× in, option-click = 2× out.
            let factor: Float = event.modifierFlags.contains(.option) ? 0.5 : 2.0
            let screen = canvasPoint(event, in: ctx)
            applyZoom(by: factor, around: screen, ctx: ctx)
        }
    }

    func keyDown(_ event: NSEvent, ctx: ToolContext) {}

    // MARK: - Helpers

    private func applyZoom(by factor: Float, around screen: SIMD2<Float>, ctx: ToolContext) {
        let oldView = ctx.document.view
        let newZoom = CanvasMath.clampZoom(oldView.zoom * factor)
        let viewport = viewportSize(ctx)
        let newCenter = CanvasMath.centerForZoomAround(
            cursor: screen,
            view: oldView,
            viewportSize: viewport,
            newZoom: newZoom
        )
        ctx.document.view.zoom = newZoom
        ctx.document.view.center = newCenter
        ctx.canvas?.documentDidChange()
        NotificationCenter.default.post(name: .chopViewDidChange, object: ctx.canvas)
    }

    private func canvasPoint(_ event: NSEvent, in ctx: ToolContext) -> SIMD2<Float> {
        guard let canvas = ctx.canvas else { return .zero }
        let p = canvas.convert(event.locationInWindow, from: nil)
        let backing = canvas.convertToBacking(p)
        // Flip y: AppKit point origin is bottom-left; our viewport math uses top-left.
        let drawable = canvas.drawableSize
        return SIMD2<Float>(Float(backing.x), Float(drawable.height - backing.y))
    }

    private func viewportSize(_ ctx: ToolContext) -> SIMD2<Float> {
        guard let canvas = ctx.canvas else { return .zero }
        let s = canvas.drawableSize
        return SIMD2<Float>(Float(s.width), Float(s.height))
    }
}
