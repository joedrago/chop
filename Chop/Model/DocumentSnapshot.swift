import CoreGraphics
import Foundation

/// A complete snapshot of a Document's pixel state and dimensions, used by
/// pixel-mutating actions to revert (PLAN.md §7).
public struct DocumentSnapshot {
    public let width: Int
    public let height: Int
    public let layerImages: [(LayerId, CGImage)]
    public let activeLayer: LayerId
    public let selection: Selection

    init(_ doc: Document) {
        self.width = doc.width
        self.height = doc.height
        self.layerImages = doc.layers.map { ($0.id, $0.pixels.cgImage) }
        self.activeLayer = doc.activeLayer
        self.selection = doc.selection
    }
}

extension Document {
    /// Capture an immutable snapshot. Used by pixel-mutating actions.
    public func snapshot() -> DocumentSnapshot {
        DocumentSnapshot(self)
    }

    /// Restore from a snapshot. Bumps `textureRevision` so renderers know to
    /// re-upload (PLAN.md §6).
    public func restore(from snap: DocumentSnapshot) {
        self.setDimensions(width: snap.width, height: snap.height)
        // Map snapshot's per-layer images back onto the existing Layer
        // structs. v1 invariant: one layer; this is still written generically.
        let imagesByLayer = Dictionary(uniqueKeysWithValues: snap.layerImages)
        var rebuilt: [Layer] = []
        for var layer in layers {
            if let image = imagesByLayer[layer.id] {
                layer.pixels = ImageBuffer(cgImage: image)
            }
            rebuilt.append(layer)
        }
        self.setLayers(rebuilt)
        self.activeLayer = snap.activeLayer
        self.selection = snap.selection
        self.bumpTextureRevision()
    }
}
