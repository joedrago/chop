import CoreGraphics
import Foundation

/// Crops every layer to the active selection rectangle and updates document
/// dimensions (PLAN.md §7). Reverts via a `DocumentSnapshot`.
@MainActor
final class CropAction: Action {
    let label: String = "Crop"
    let rect: IRect
    private var snapshot: DocumentSnapshot?

    init(rect: IRect) {
        self.rect = rect
    }

    func apply(to document: Document) throws {
        guard !rect.isEmpty else { throw ChopError.invalidGeometry }
        let clamped = rect.clamped(toImageWidth: document.width, height: document.height)
        guard !clamped.isEmpty else { throw ChopError.invalidGeometry }

        snapshot = document.snapshot()

        for layer in document.layers {
            let cropped = try cropPixels(layer.pixels, to: clamped)
            document.updateLayerPixels(id: layer.id, pixels: cropped)
        }
        document.setDimensions(width: clamped.width, height: clamped.height)
        // Crop discards the selection — there's no canonical mapping back.
        document.selection = .none
        // Re-center the view on the new image.
        document.view.center = SIMD2<Float>(
            Float(clamped.width) / 2,
            Float(clamped.height) / 2
        )
        document.bumpTextureRevision()
    }

    func revert(from document: Document) throws {
        guard let snap = snapshot else { return }
        document.restore(from: snap)
    }

    private func cropPixels(_ buffer: ImageBuffer, to r: IRect) throws -> ImageBuffer {
        // Project convention: pixel data is top-left aligned everywhere. CGImage
        // stores rows top-down, and `cropping(to:)` interprets the rect in that
        // same top-left pixel grid — so we pass the IRect through unmodified.
        let srcRect = CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
        guard let cropped = buffer.cgImage.cropping(to: srcRect) else {
            throw ChopError.cropFailed
        }
        // .cropping(to:) returns a CGImage that lazily references the source's
        // pixel storage. Realize it into its own buffer so the snapshot can
        // hold the original storage alive without keeping the cropped one
        // pinned to the original strides.
        return ImageBuffer(cgImage: realize(cropped))
    }

    /// Force-render `image` into its own backing store to detach it from the
    /// shared parent storage of `CGImage.cropping(to:)`.
    private func realize(_ image: CGImage) -> CGImage {
        let cs = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard
            let ctx = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: cs,
                bitmapInfo: info.rawValue
            )
        else {
            return image
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage() ?? image
    }
}
