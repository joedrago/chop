import simd

/// View ↔ image-space coordinate math
///
/// `viewportSize` is the on-screen canvas size in *backing* pixels. This is what
/// `MTKView.drawableSize` reports and what `drawableSize.width / .height` give us.
public enum CanvasMath {
    /// Image-space → screen-space.
    /// screen(p) = viewportCenter + (p - view.center) * view.zoom.
    public static func screen(
        _ point: SIMD2<Float>,
        view: ViewState,
        viewportSize: SIMD2<Float>
    ) -> SIMD2<Float> {
        let viewportCenter = viewportSize * 0.5
        return viewportCenter + (point - view.center) * view.zoom
    }

    /// Screen-space → image-space.
    /// image(s) = view.center + (s - viewportCenter) / view.zoom.
    public static func imageSpace(
        _ screen: SIMD2<Float>,
        view: ViewState,
        viewportSize: SIMD2<Float>
    ) -> SIMD2<Float> {
        let viewportCenter = viewportSize * 0.5
        return view.center + (screen - viewportCenter) / view.zoom
    }

    /// Apply a zoom-around-cursor change. Returns a new center that keeps the
    /// image-space point under the cursor pinned at the same screen position.
    public static func centerForZoomAround(
        cursor: SIMD2<Float>,
        view: ViewState,
        viewportSize: SIMD2<Float>,
        newZoom: Float
    ) -> SIMD2<Float> {
        guard view.zoom > 0, newZoom > 0 else { return view.center }
        let viewportCenter = viewportSize * 0.5
        return view.center + (cursor - viewportCenter) * (1 / view.zoom - 1 / newZoom)
    }

    /// Compute "fit-to-window" zoom: the largest zoom that keeps the entire
    /// image inside the viewport.
    public static func fitZoom(
        imageSize: SIMD2<Float>,
        viewportSize: SIMD2<Float>
    ) -> Float {
        guard imageSize.x > 0, imageSize.y > 0 else { return 1 }
        return min(viewportSize.x / imageSize.x, viewportSize.y / imageSize.y)
    }

    /// Clamp zoom into a sane range.
    public static func clampZoom(_ z: Float) -> Float {
        min(max(z, 0.01), 64.0)
    }
}
