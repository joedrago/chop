import Foundation

public struct LayerId: Hashable, Equatable {
    public let raw: UInt64
    public init(raw: UInt64) { self.raw = raw }
}

public enum BlendMode {
    case normal
}

/// One layer of an image document. v1 invariant: `layers.count == 1` and the
/// layer's pixel buffer matches the document's `width × height`. (PLAN.md §4.)
public struct Layer: Identifiable {
    public var id: LayerId
    public var name: String
    public var visible: Bool
    public var opacity: Float
    public var blend: BlendMode
    public var pixels: ImageBuffer

    public init(
        id: LayerId,
        name: String,
        visible: Bool = true,
        opacity: Float = 1.0,
        blend: BlendMode = .normal,
        pixels: ImageBuffer
    ) {
        self.id = id
        self.name = name
        self.visible = visible
        self.opacity = opacity
        self.blend = blend
        self.pixels = pixels
    }
}
