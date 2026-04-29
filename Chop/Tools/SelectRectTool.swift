import AppKit
import simd

/// Drag a rectangle in image-space (PLAN.md §8). v1: replaces the existing
/// selection; modifier keys for add/subtract come later.
@MainActor
final class SelectRectTool: Tool {
    let id: ToolId = .rectSelect
    let displayName: String = "Rectangle Select"
    let cursor: NSCursor = .crosshair

    private var dragOriginImage: SIMD2<Float>?
    private var dragStartSelection: Selection = .none
    private var lastPreview: IRect?

    func mouseDown(_ event: NSEvent, ctx: ToolContext) {
        let p = imagePoint(event, in: ctx)
        dragOriginImage = p
        dragStartSelection = ctx.document.selection
        lastPreview = nil
        // Live-update the document's selection so the marching-ants overlay
        // animates in real time. We commit the final selection as an Action
        // on mouseUp; the in-between updates are not undoable.
        ctx.document.selection = .none
        ctx.canvas?.selectionDidChange()
    }

    func mouseDragged(_ event: NSEvent, ctx: ToolContext) {
        guard let origin = dragOriginImage else { return }
        let p = imagePoint(event, in: ctx)
        let r = makeRect(from: origin, to: p, in: ctx.document)
        if r != lastPreview {
            lastPreview = r
            ctx.document.selection = r.isEmpty ? .none : .rect(r)
            ctx.canvas?.selectionDidChange()
        }
    }

    func mouseUp(_ event: NSEvent, ctx: ToolContext) {
        defer {
            dragOriginImage = nil
            dragStartSelection = .none
            lastPreview = nil
        }
        guard let origin = dragOriginImage else { return }
        let p = imagePoint(event, in: ctx)
        let r = makeRect(from: origin, to: p, in: ctx.document)
        let newSelection: Selection = r.isEmpty ? .none : .rect(r)
        // Revert to the prior selection so commit() applies the action with
        // the prior state intact, then commit.
        ctx.document.selection = dragStartSelection
        ctx.canvas?.selectionDidChange()
        if let host = ctx.documentHost {
            host.commit(
                SetSelectionAction(prior: dragStartSelection, new: newSelection)
            )
        } else {
            ctx.document.selection = newSelection
            ctx.canvas?.selectionDidChange()
        }
    }

    func keyDown(_ event: NSEvent, ctx: ToolContext) {}

    // MARK: - Helpers

    private func makeRect(
        from a: SIMD2<Float>,
        to b: SIMD2<Float>,
        in doc: Document
    ) -> IRect {
        let ax = Int(a.x.rounded())
        let ay = Int(a.y.rounded())
        let bx = Int(b.x.rounded())
        let by = Int(b.y.rounded())
        let r = IRect.fromTwoPoints((ax, ay), (bx, by))
        return r.clamped(toImageWidth: doc.width, height: doc.height)
    }

    private func imagePoint(_ event: NSEvent, in ctx: ToolContext) -> SIMD2<Float> {
        guard let canvas = ctx.canvas else { return .zero }
        let p = canvas.convert(event.locationInWindow, from: nil)
        let backing = canvas.convertToBacking(p)
        let drawable = canvas.drawableSize
        let screen = SIMD2<Float>(Float(backing.x), Float(drawable.height - backing.y))
        let viewport = SIMD2<Float>(Float(drawable.width), Float(drawable.height))
        return CanvasMath.imageSpace(screen, view: ctx.document.view, viewportSize: viewport)
    }
}
