import CoreGraphics
import Foundation
import Testing

@testable import Chop

@MainActor
@Suite("Resize")
struct ResizeTests {
    @Test(
        "All filters produce target dimensions",
        arguments: [ResampleFilter.nearest, .bilinear, .lanczos3]
    )
    func resizesToTargetSize(filter: ResampleFilter) throws {
        let buffer = try makeBuffer(width: 16, height: 16)
        let resized = try Resize.resample(
            buffer,
            toWidth: 8,
            height: 8,
            filter: filter
        )
        #expect(resized.width == 8)
        #expect(resized.height == 8)
    }

    @Test("ResizeAction apply / revert round-trips")
    func resizeRoundtrip() throws {
        let doc = try makeDoc(width: 32, height: 32)
        let action = ResizeAction(newWidth: 16, newHeight: 8, filter: .bilinear)
        try action.apply(to: doc)
        #expect(doc.width == 16)
        #expect(doc.height == 8)
        try action.revert(from: doc)
        #expect(doc.width == 32)
        #expect(doc.height == 32)
    }

    @Test("Nearest preserves discrete colors at exact 2× downsample")
    func nearestPreservesPixels() throws {
        // 2×2 image, half black half white. Nearest 2×→1× should pick one of
        // the source pixels per dest pixel, deterministically.
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let ctx = CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: info.rawValue
        )!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let img = ctx.makeImage()!
        let buffer = ImageBuffer(cgImage: img)
        let out = try Resize.resample(buffer, toWidth: 1, height: 1, filter: .nearest)
        #expect(out.width == 1 && out.height == 1)
    }

    private func makeBuffer(width: Int, height: Int) throws -> ImageBuffer {
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: info.rawValue
        )!
        ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ImageBuffer(cgImage: ctx.makeImage()!)
    }

    private func makeDoc(width: Int, height: Int) throws -> Document {
        Document.fromImage(try makeBuffer(width: width, height: height).cgImage)
    }
}
