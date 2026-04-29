import Foundation
import Testing
import simd

@testable import Chop

@Suite("CanvasMath")
struct CanvasMathTests {
    @Test("Image-space → screen → image-space round-trips")
    func roundtrip() {
        let view = ViewState(zoom: 2.0, center: SIMD2<Float>(50, 30))
        let viewport = SIMD2<Float>(800, 600)
        let p = SIMD2<Float>(75, 40)
        let s = CanvasMath.screen(p, view: view, viewportSize: viewport)
        let p2 = CanvasMath.imageSpace(s, view: view, viewportSize: viewport)
        #expect(abs(p2.x - p.x) < 1e-3)
        #expect(abs(p2.y - p.y) < 1e-3)
    }

    @Test("Zoom-around-cursor keeps the cursor pinned")
    func zoomAroundCursorPin() {
        let view = ViewState(zoom: 1.0, center: SIMD2<Float>(100, 100))
        let viewport = SIMD2<Float>(400, 400)
        let cursor = SIMD2<Float>(150, 100)
        let imagePtUnderCursor = CanvasMath.imageSpace(cursor, view: view, viewportSize: viewport)
        let newZoom: Float = 4.0
        let newCenter = CanvasMath.centerForZoomAround(
            cursor: cursor,
            view: view,
            viewportSize: viewport,
            newZoom: newZoom
        )
        let newView = ViewState(zoom: newZoom, center: newCenter)
        let imagePtUnderCursorNow = CanvasMath.imageSpace(
            cursor,
            view: newView,
            viewportSize: viewport
        )
        #expect(abs(imagePtUnderCursorNow.x - imagePtUnderCursor.x) < 1e-3)
        #expect(abs(imagePtUnderCursorNow.y - imagePtUnderCursor.y) < 1e-3)
    }

    @Test("fitZoom equals min of axis ratios")
    func fit() {
        let img = SIMD2<Float>(2000, 1000)
        let viewport = SIMD2<Float>(800, 600)
        // 800/2000 = 0.4, 600/1000 = 0.6 → fit = 0.4
        #expect(abs(CanvasMath.fitZoom(imageSize: img, viewportSize: viewport) - 0.4) < 1e-3)
    }

    @Test("clampZoom bounds are respected")
    func clamp() {
        #expect(CanvasMath.clampZoom(0.0001) == 0.01)
        #expect(CanvasMath.clampZoom(1000) == 64.0)
        #expect(abs(CanvasMath.clampZoom(2.5) - 2.5) < 1e-6)
    }
}
