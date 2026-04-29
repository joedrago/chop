import CoreGraphics
import ImageIO

/// EXIF Orientation values (1…8) per the EXIF spec.
/// ImageIO surfaces this via `kCGImagePropertyOrientation` but does NOT bake
/// it into pixels. We do.
enum EXIFOrientation: Int {
    case up = 1
    case upMirrored = 2
    case down = 3
    case downMirrored = 4
    case leftMirrored = 5
    case right = 6
    case rightMirrored = 7
    case left = 8

    /// Does this orientation swap width/height of the resulting image?
    var swapsAxes: Bool {
        switch self {
        case .leftMirrored, .right, .rightMirrored, .left: return true
        default: return false
        }
    }
}

/// Reads orientation from the source's first image and bakes it in by drawing
/// into a fresh CGContext. Color space is preserved; output bitmap layout is
/// premultiplied last alpha (8-bit) — adequate for v1 since save round-trips
/// produce equivalent pixel values for both PNG (lossless) and JPEG (no alpha).
func applyEXIFOrientation(_ image: CGImage, source: CGImageSource) -> CGImage {
    let props =
        CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    let raw = props[kCGImagePropertyOrientation] as? Int ?? 1
    let orientation = EXIFOrientation(rawValue: raw) ?? .up
    if orientation == .up {
        return image
    }
    return bakingOrientation(into: image, orientation: orientation)
}

/// Re-render `image` so that the orientation is applied to the pixels.
/// Returns the input on failure rather than throwing — orientation is a
/// best-effort fix, not a hard prerequisite.
func bakingOrientation(into image: CGImage, orientation: EXIFOrientation) -> CGImage {
    let srcW = image.width
    let srcH = image.height
    let dstW = orientation.swapsAxes ? srcH : srcW
    let dstH = orientation.swapsAxes ? srcW : srcH

    let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

    guard
        let ctx = CGContext(
            data: nil,
            width: dstW,
            height: dstH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        )
    else {
        return image
    }

    // Build the affine transform that maps source pixels to dest pixels, in
    // a coordinate system whose origin is the bottom-left.
    let dstWf = CGFloat(dstW)
    let dstHf = CGFloat(dstH)
    var transform = CGAffineTransform.identity

    switch orientation {
    case .up:
        break
    case .upMirrored:
        transform = transform.translatedBy(x: dstWf, y: 0).scaledBy(x: -1, y: 1)
    case .down:
        transform = transform.translatedBy(x: dstWf, y: dstHf).rotated(by: .pi)
    case .downMirrored:
        transform = transform.translatedBy(x: 0, y: dstHf).scaledBy(x: 1, y: -1)
    case .leftMirrored:
        transform = transform.rotated(by: .pi / 2).scaledBy(x: 1, y: -1)
    case .right:
        transform = transform.translatedBy(x: dstWf, y: 0).rotated(by: .pi / 2)
    case .rightMirrored:
        transform = transform.translatedBy(x: dstWf, y: dstHf).rotated(by: -.pi / 2)
            .scaledBy(x: -1, y: 1)
    case .left:
        transform = transform.translatedBy(x: 0, y: dstHf).rotated(by: -.pi / 2)
    }

    ctx.concatenate(transform)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: srcW, height: srcH))

    return ctx.makeImage() ?? image
}
