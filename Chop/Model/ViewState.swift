import simd

/// Per-document camera state
/// `zoom` = pixels-on-screen per image-pixel (1.0 = 100%).
/// `center` = image-space coordinate at the viewport's center.
public struct ViewState: Equatable {
    public var zoom: Float
    public var center: SIMD2<Float>

    public init(zoom: Float = 1.0, center: SIMD2<Float> = .zero) {
        self.zoom = zoom
        self.center = center
    }
}
