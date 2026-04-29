import AppKit
import simd

/// Drag = move view.center by -deltaScreen / zoom.
@MainActor
final class PanTool: Tool {
    let id: ToolId = .pan
    let displayName: String = "Hand"
    let cursor: NSCursor = .openHand

    private var dragging: Bool = false

    func mouseDown(_ event: NSEvent, ctx: ToolContext) {
        dragging = true
        NSCursor.closedHand.set()
    }

    func mouseDragged(_ event: NSEvent, ctx: ToolContext) {
        guard dragging else { return }
        let dx = Float(event.deltaX)
        let dy = Float(event.deltaY)
        // event.deltaY is positive when the mouse moves UP on macOS; we want
        // dragging up to reveal more of the bottom of the image (i.e. center.y
        // increases). So the formula matches the PLAN exactly.
        let zoom = ctx.document.view.zoom
        guard zoom > 0 else { return }
        ctx.document.view.center.x -= dx / zoom
        ctx.document.view.center.y -= dy / zoom
        ctx.canvas?.documentDidChange()
        NotificationCenter.default.post(name: .chopViewDidChange, object: ctx.canvas)
    }

    func mouseUp(_ event: NSEvent, ctx: ToolContext) {
        dragging = false
        NSCursor.openHand.set()
    }

    func keyDown(_ event: NSEvent, ctx: ToolContext) {}
}
