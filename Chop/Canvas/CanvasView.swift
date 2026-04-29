import AppKit
import CoreGraphics
import Metal
import MetalKit
import simd

/// MTKView subclass that renders `document.composite()` as a textured quad with
/// nearest-neighbor magnification.
@MainActor
final class CanvasView: MTKView {
    weak var document: Document?

    private var lastRevision: UInt64 = 0
    private var texture: MTLTexture?

    /// True when a fit-to-window is queued. The fit can't always happen
    /// synchronously because Auto Layout may not have given the canvas a
    /// non-zero `drawableSize` yet — so we set this flag and let `draw()`
    /// (which is only called once the drawable is valid) perform it.
    private var fitPending: Bool = false

    /// Request a re-fit: zoom-to-window and re-center on the image. Performs
    /// it immediately if the canvas is already laid out; otherwise the next
    /// `draw()` will do it. Used both on initial document load and after
    /// dimension-changing actions like Crop or Resize.
    func requestFitToWindow() {
        fitPending = true
        performFitIfPossible()
    }

    override init(frame frameRect: NSRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device ?? MetalContext.device)
        configure()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        // EDR-ready.
        colorPixelFormat = .rgba16Float
        framebufferOnly = false
        clearColor = MTLClearColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1.0)
        enableSetNeedsDisplay = true
        isPaused = true
        autoResizeDrawable = true
        layer?.isOpaque = true
        wantsLayer = true
        if let metalLayer = layer as? CAMetalLayer {
            metalLayer.wantsExtendedDynamicRangeContent = true
            metalLayer.colorspace = nil  // let CG infer from layer & display
        }
        enableFileDrops()
    }

    func documentDidChange() {
        needsDisplay = true
        updateSelectionOverlay()
    }

    override func draw(_ dirtyRect: NSRect) {
        // Now that drawableSize is guaranteed non-zero (we wouldn't get here
        // otherwise), perform any pending fit-to-window.
        performFitIfPossible()

        guard
            let device = device,
            let drawable = currentDrawable,
            let pass = currentRenderPassDescriptor,
            let queue = MetalContext.queue,
            let buffer = queue.makeCommandBuffer()
        else {
            return
        }

        if let doc = document {
            ensureTextureUpToDate(doc: doc, device: device)
        } else {
            texture = nil
        }

        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "ChopCanvas"

        if let doc = document, let tex = texture,
            let pipeline = MetalContext.pipelineCache.quad(format: colorPixelFormat),
            let sampler = MetalContext.pipelineCache.nearestSampler()
        {
            // Compute clip-space quad based on view.zoom + view.center.
            let drawableSize = self.drawableSize
            let dw = Float(drawableSize.width)
            let dh = Float(drawableSize.height)
            let imgW = Float(doc.width)
            let imgH = Float(doc.height)

            // Per-pixel scale in screen pixels. drawableSize is already in
            // backing pixels, so view.zoom translates 1:1.
            let zoom = doc.view.zoom
            let imgPxOnScreenW = imgW * zoom
            let imgPxOnScreenH = imgH * zoom

            // Map quad coord c ∈ [0,1]^2 → image pixel (c.x*imgW, c.y*imgH)
            //                       → screen pixel offset from canvas center
            //                       → clip-space (canvas spans [-1,+1]).
            //
            // clip.x(c) = (c.x*imgW - viewCx) * zoom / (dw/2)
            //           = c.x * (imgW * zoom / (dw/2))   +  (-viewCx * zoom / (dw/2))
            // clip.y(c) = -(c.y*imgH - viewCy) * zoom / (dh/2)
            //           = c.y * -(imgH * zoom / (dh/2))  +  ( viewCy * zoom / (dh/2))
            //   (the leading minus on clip.y flips screen-y-down to clip-y-up)
            //
            // So:    scale.x =  2 * imgPxOnScreenW / dw,   translate.x = -2 * cx * zoom / dw
            //        scale.y = -2 * imgPxOnScreenH / dh,   translate.y =  2 * cy * zoom / dh
            let cx = doc.view.center.x
            let cy = doc.view.center.y
            let scaleX = (imgPxOnScreenW / dw) * 2.0
            let scaleY = -(imgPxOnScreenH / dh) * 2.0
            let translateX = -2.0 * cx * zoom / dw
            let translateY = 2.0 * cy * zoom / dh
            var uniforms = QuadUniforms(
                scale: SIMD2<Float>(scaleX, scaleY),
                translate: SIMD2<Float>(translateX, translateY),
                imageSize: SIMD2<Float>(imgW, imgH),
                zoom: zoom,
                _pad: 0
            )

            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<QuadUniforms>.size, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<QuadUniforms>.size, index: 0)
            encoder.setFragmentTexture(tex, index: 0)
            encoder.setFragmentSamplerState(sampler, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    private func ensureTextureUpToDate(doc: Document, device: MTLDevice) {
        if doc.textureRevision == lastRevision, texture != nil { return }
        if let tex = uploadTexture(from: doc.composite(), device: device) {
            texture = tex
            lastRevision = doc.textureRevision
        }
    }

    private func uploadTexture(from cgImage: CGImage, device: MTLDevice) -> MTLTexture? {
        // Use MTKTextureLoader for the heavy lifting; it preserves the source
        // CGImage's color space when possible.
        let loader = MTKTextureLoader(device: device)
        let opts: [MTKTextureLoader.Option: Any] = [
            .SRGB: false,
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue),
            .generateMipmaps: false,
        ]
        return try? loader.newTexture(cgImage: cgImage, options: opts)
    }

    /// If a fit is pending and the canvas is laid out, set view.zoom to
    /// fill the canvas and re-center the camera on the image. Otherwise
    /// leave state alone.
    private func performFitIfPossible() {
        guard fitPending, let doc = document else { return }
        let drawable = drawableSize
        guard drawable.width > 0, drawable.height > 0 else { return }
        let viewport = SIMD2<Float>(Float(drawable.width), Float(drawable.height))
        let imageSize = SIMD2<Float>(Float(doc.width), Float(doc.height))
        let fit = CanvasMath.fitZoom(imageSize: imageSize, viewportSize: viewport)
        doc.view.zoom = CanvasMath.clampZoom(fit)
        doc.view.center = imageSize * 0.5
        fitPending = false
        // External callers (e.g. F key, post-crop refit) reach this path
        // outside `draw()`, so the canvas needs an explicit redraw + overlay
        // refresh — without this, the zoom changes silently. When called
        // from inside `draw()` itself, the redundant `needsDisplay = true`
        // is harmless.
        needsDisplay = true
        updateSelectionOverlay()
        // Let the window controller refresh chrome (scrollers, status bar)
        // now that we have a real zoom + center.
        NotificationCenter.default.post(name: .chopViewDidChange, object: self)
    }
}

private struct QuadUniforms {
    var scale: SIMD2<Float>
    var translate: SIMD2<Float>
    var imageSize: SIMD2<Float>
    var zoom: Float
    var _pad: Float
}
