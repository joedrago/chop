import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Encoder knobs for one save invocation. The set of relevant fields depends
/// on the type — JPEG cares about quality, PNG cares about interlace.
public struct SaveOptions {
    public enum Format: String {
        case png = "public.png"
        case jpeg = "public.jpeg"

        public init?(uti typeName: String) {
            switch typeName {
            case "public.png": self = .png
            case "public.jpeg", "public.jpg": self = .jpeg
            default: return nil
            }
        }

        public var defaultExtension: String {
            switch self {
            case .png: return "png"
            case .jpeg: return "jpg"
            }
        }
    }

    public var jpegQuality: Double = 0.92
    public var jpegProgressive: Bool = false
    public var pngInterlaced: Bool = false

    public init() {}
}

/// Build the ImageIO option dictionary for a given format + SaveOptions.
/// PLAN.md §9 lists the supported keys; subsampling and PNG compression level
/// are not directly exposed by ImageIO and fall back to system defaults.
func imageIODestinationOptions(
    for format: SaveOptions.Format,
    options: SaveOptions
)
    -> [CFString: Any]
{
    switch format {
    case .png:
        var dict: [CFString: Any] = [:]
        dict[kCGImagePropertyPNGDictionary] =
            [
                kCGImagePropertyPNGInterlaceType: options.pngInterlaced ? 1 : 0
            ] as CFDictionary
        return dict
    case .jpeg:
        var dict: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: options.jpegQuality
        ]
        dict[kCGImagePropertyJFIFDictionary] =
            [
                kCGImagePropertyJFIFIsProgressive: options.jpegProgressive
            ] as CFDictionary
        return dict
    }
}
