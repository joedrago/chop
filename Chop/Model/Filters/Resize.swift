import Accelerate
import CoreGraphics
import CoreImage
import Foundation

/// Pixel-level resize entry point.
///
/// We dispatch by filter to one of three back-ends:
///   - `nearest`  → CGContext with `interpolationQuality = .none`
///   - `bilinear` → CGContext with `interpolationQuality = .medium`
///   - `lanczos3` → Core Image `CILanczosScaleTransform`
///
/// All three preserve the source's color space when possible; the bitmap
/// layout for nearest/bilinear is 8-bit premultiplied last alpha (matches the
/// EXIF orientation path). Lanczos uses Core Image's working color space.
public enum Resize {
    public static func resample(
        _ buffer: ImageBuffer,
        toWidth newWidth: Int,
        height newHeight: Int,
        filter: ResampleFilter
    ) throws -> ImageBuffer {
        precondition(newWidth > 0 && newHeight > 0, "Resize must produce positive dimensions.")
        let src = buffer.cgImage
        switch filter {
        case .nearest:
            return ImageBuffer(
                cgImage: try resampleViaCG(
                    src,
                    toWidth: newWidth,
                    height: newHeight,
                    quality: .none
                )
            )
        case .bilinear:
            return ImageBuffer(
                cgImage: try resampleViaCG(
                    src,
                    toWidth: newWidth,
                    height: newHeight,
                    quality: .medium
                )
            )
        case .lanczos3:
            return ImageBuffer(
                cgImage: try resampleViaCoreImageLanczos(
                    src,
                    toWidth: newWidth,
                    height: newHeight
                )
            )
        }
    }

    private static func resampleViaCG(
        _ src: CGImage,
        toWidth newWidth: Int,
        height newHeight: Int,
        quality: CGInterpolationQuality
    ) throws -> CGImage {
        let cs = src.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard
            let ctx = CGContext(
                data: nil,
                width: newWidth,
                height: newHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: cs,
                bitmapInfo: info.rawValue
            )
        else {
            throw ChopError.resizeFailed
        }
        ctx.interpolationQuality = quality
        ctx.draw(src, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        guard let out = ctx.makeImage() else {
            throw ChopError.resizeFailed
        }
        return out
    }

    private static let ciContext: CIContext = {
        // Software renderer is fine for one-shot resize; avoids any GPU
        // synchronization cost at action-commit time.
        CIContext(options: [.useSoftwareRenderer: true])
    }()

    private static func resampleViaCoreImageLanczos(
        _ src: CGImage,
        toWidth newWidth: Int,
        height newHeight: Int
    ) throws -> CGImage {
        let inputCI = CIImage(cgImage: src)
        let scaleX = CGFloat(newWidth) / CGFloat(src.width)
        let scaleY = CGFloat(newHeight) / CGFloat(src.height)
        // The Lanczos filter in Core Image takes a uniform `scale` and an
        // `aspectRatio` (= horizontal stretch). Decompose accordingly.
        let scale = scaleY
        let aspect = scaleX / scaleY
        guard
            let filter = CIFilter(
                name: "CILanczosScaleTransform",
                parameters: [
                    kCIInputImageKey: inputCI,
                    kCIInputScaleKey: scale,
                    kCIInputAspectRatioKey: aspect,
                ]
            )
        else {
            throw ChopError.resizeFailed
        }
        guard let output = filter.outputImage else {
            throw ChopError.resizeFailed
        }
        // Core Image's output may have a non-(0,0) origin; crop to the
        // expected target rect.
        let rect = CGRect(x: 0, y: 0, width: newWidth, height: newHeight)
        guard
            let cgOut = ciContext.createCGImage(
                output,
                from: rect,
                format: .RGBA8,
                colorSpace: src.colorSpace ?? CGColorSpaceCreateDeviceRGB()
            )
        else {
            throw ChopError.resizeFailed
        }
        return cgOut
    }
}
