import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Encode `image` to a Data blob via CGImageDestination.
func encode(
    _ image: CGImage,
    format: SaveOptions.Format,
    options: SaveOptions
) throws -> Data {
    let mut = NSMutableData()
    let utt: UTType
    switch format {
    case .png: utt = .png
    case .jpeg: utt = .jpeg
    }
    guard
        let dest = CGImageDestinationCreateWithData(
            mut,
            utt.identifier as CFString,
            1,
            nil
        )
    else {
        throw ChopError.encodeFailed
    }
    let opts = imageIODestinationOptions(for: format, options: options)
    CGImageDestinationAddImage(dest, image, opts as CFDictionary)
    guard CGImageDestinationFinalize(dest) else {
        throw ChopError.encodeFailed
    }
    return mut as Data
}
