import AppKit
import QuartzCore
import simd

/// Selection-overlay support on `CanvasView`
///
/// The marching-ants layer is positioned in *backing-pixel* space (matching
/// the MTKView's drawableSize). The CAShapeLayer's path is the selection
/// rectangle expressed in screen-backing coordinates.
extension CanvasView {
    func selectionDidChange() {
        updateSelectionOverlay()
        // Refresh chrome (info palette in particular) so the selection rect
        // readout updates on every drag tick, not just commit.
        NotificationCenter.default.post(name: .chopViewDidChange, object: self)
    }

    func updateSelectionOverlay() {
        guard let doc = document else {
            ants?.update(rectInScreen: nil)
            return
        }
        ensureAntsLayer()
        switch doc.selection {
        case .none:
            ants?.update(rectInScreen: nil)
        case .rect(let r):
            ants?.update(rectInScreen: rectInScreen(r, doc: doc))
        }
    }

    private func rectInScreen(_ r: IRect, doc: Document) -> CGRect {
        // CanvasMath operates in *backing pixels* (view.zoom is image-px-per-
        // backing-px). Run the math against drawableSize, then divide by the
        // backing scale factor to land in the point-space the CALayer uses.
        let drawable = drawableSize
        let viewport = SIMD2<Float>(Float(drawable.width), Float(drawable.height))
        let topLeft = CanvasMath.screen(
            SIMD2<Float>(Float(r.x), Float(r.y)),
            view: doc.view,
            viewportSize: viewport
        )
        let botRight = CanvasMath.screen(
            SIMD2<Float>(Float(r.x + r.width), Float(r.y + r.height)),
            view: doc.view,
            viewportSize: viewport
        )
        let bsf = CGFloat(window?.backingScaleFactor ?? 1)
        return CGRect(
            x: CGFloat(min(topLeft.x, botRight.x)) / bsf,
            y: CGFloat(min(topLeft.y, botRight.y)) / bsf,
            width: CGFloat(abs(botRight.x - topLeft.x)) / bsf,
            height: CGFloat(abs(botRight.y - topLeft.y)) / bsf
        )
    }

    private static var kAntsKey: UInt8 = 0
    var ants: MarchingAntsLayer? {
        get { objc_getAssociatedObject(self, &Self.kAntsKey) as? MarchingAntsLayer }
        set { objc_setAssociatedObject(self, &Self.kAntsKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    private func ensureAntsLayer() {
        if ants != nil { return }
        guard let host = layer else { return }
        let layer = MarchingAntsLayer()
        layer.frame = bounds
        layer.zPosition = 100
        // Use a *flipped* layer for screen math: y-down to match the math we
        // use elsewhere.
        layer.isGeometryFlipped = true
        // Clip ants to the canvas viewport so the marching rect doesn't bleed
        // over the side panels when the image extends past the canvas.
        layer.masksToBounds = true
        host.addSublayer(layer)
        ants = layer
    }

    public override func layout() {
        super.layout()
        ants?.frame = bounds
        updateSelectionOverlay()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateSelectionOverlay()
    }
}
