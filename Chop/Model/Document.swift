import CoreGraphics
import Foundation
import simd

/// Pure-Swift data model — the AppKit `ChopDocument` wraps this.
/// Distinct from `ChopDocument` (the NSDocument subclass).
public final class Document {
    public private(set) var width: Int
    public private(set) var height: Int
    public private(set) var layers: [Layer]
    public var activeLayer: LayerId
    public var selection: Selection
    public var view: ViewState
    public var activeToolId: ToolId
    public private(set) var textureRevision: UInt64

    private static var nextLayerSeq: UInt64 = 0

    public init(width: Int, height: Int, layers: [Layer], activeLayer: LayerId) {
        precondition(width > 0 && height > 0, "Document dimensions must be positive.")
        precondition(layers.count == 1, "v1 invariant: exactly one layer.")
        self.width = width
        self.height = height
        self.layers = layers
        self.activeLayer = activeLayer
        self.selection = .none
        self.view = ViewState()
        self.activeToolId = .pan
        self.textureRevision = 1
    }

    /// Build a document from a single decoded image. The provided `name` is
    /// used as the Background layer's label.
    public static func fromImage(_ image: CGImage, name: String = "Background") -> Document {
        let pixels = ImageBuffer(cgImage: image)
        let id = nextLayerId()
        let layer = Layer(id: id, name: name, pixels: pixels)
        return Document(
            width: image.width,
            height: image.height,
            layers: [layer],
            activeLayer: id
        )
    }

    public static func nextLayerId() -> LayerId {
        nextLayerSeq += 1
        return LayerId(raw: nextLayerSeq)
    }

    /// v1: a single layer's pixels = the composite.
    public func composite() -> CGImage {
        assert(layers.count == 1, "v1 invariant: exactly one layer.")
        return layers[0].pixels.cgImage
    }

    /// Alias for the save path.
    public func flatten() -> CGImage { composite() }

    public func bumpTextureRevision() {
        textureRevision &+= 1
    }

    func setDimensions(width: Int, height: Int) {
        precondition(width > 0 && height > 0, "Document dimensions must be positive.")
        self.width = width
        self.height = height
    }

    func setLayers(_ layers: [Layer]) {
        precondition(layers.count == 1, "v1 invariant: exactly one layer.")
        self.layers = layers
    }

    /// Replace the pixels of a single layer in place. Used by pixel-mutating
    /// actions (Crop, Resize, …) once they've produced the new buffer.
    func updateLayerPixels(id: LayerId, pixels: ImageBuffer) {
        guard let idx = layers.firstIndex(where: { $0.id == id }) else { return }
        layers[idx].pixels = pixels
    }
}
