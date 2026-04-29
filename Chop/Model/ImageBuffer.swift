import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Wraps a `CGImage` — the canonical pixel state. The CGImage carries its own
/// color space; we never strip ICC on load (PLAN.md §5).
public struct ImageBuffer {
    public let cgImage: CGImage

    public init(cgImage: CGImage) {
        self.cgImage = cgImage
    }

    public var width: Int { cgImage.width }
    public var height: Int { cgImage.height }
    public var colorSpace: CGColorSpace? { cgImage.colorSpace }

    /// Decodes a CGImage from raw image data using ImageIO and bakes in the
    /// EXIF Orientation if present (PLAN.md §5).
    public static func decode(from data: Data) throws -> ImageBuffer {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ChopError.decodeFailed
        }
        guard let raw = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ChopError.decodeFailed
        }
        let oriented = applyEXIFOrientation(raw, source: source)
        return ImageBuffer(cgImage: oriented)
    }
}

public enum ChopError: Error, LocalizedError {
    case decodeFailed
    case encodeFailed
    case unsupportedType(String)
    case invalidGeometry
    case cropFailed
    case resizeFailed

    public var errorDescription: String? {
        switch self {
        case .decodeFailed:
            return
                "Could not decode the image. The file may be corrupt or in an unsupported format."
        case .encodeFailed:
            return "Could not encode the image."
        case .unsupportedType(let t):
            return "Unsupported file type: \(t)"
        case .invalidGeometry:
            return "Invalid geometry."
        case .cropFailed:
            return "Could not crop the image."
        case .resizeFailed:
            return "Could not resize the image."
        }
    }
}
