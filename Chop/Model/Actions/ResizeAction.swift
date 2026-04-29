import CoreGraphics
import Foundation
import simd

/// Resize the entire document (every layer + canvas dims) with the chosen
/// resampling filter (PLAN.md §7 / Phase 5). Reverts via DocumentSnapshot.
@MainActor
final class ResizeAction: Action {
    let label: String = "Resize"
    let newWidth: Int
    let newHeight: Int
    let filter: ResampleFilter
    private var snapshot: DocumentSnapshot?

    init(newWidth: Int, newHeight: Int, filter: ResampleFilter) {
        self.newWidth = newWidth
        self.newHeight = newHeight
        self.filter = filter
    }

    func apply(to document: Document) throws {
        guard newWidth > 0, newHeight > 0 else { throw ChopError.invalidGeometry }
        snapshot = document.snapshot()
        for layer in document.layers {
            let resized = try Resize.resample(
                layer.pixels,
                toWidth: newWidth,
                height: newHeight,
                filter: filter
            )
            document.updateLayerPixels(id: layer.id, pixels: resized)
        }
        document.setDimensions(width: newWidth, height: newHeight)
        // Drop any selection — pixel coordinates have moved.
        document.selection = .none
        document.view.center = SIMD2<Float>(Float(newWidth) / 2, Float(newHeight) / 2)
        document.bumpTextureRevision()
    }

    func revert(from document: Document) throws {
        guard let snap = snapshot else { return }
        document.restore(from: snap)
    }
}
