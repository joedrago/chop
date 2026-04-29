import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Chop

@Suite("Save / round-trip")
struct SaveRoundtripTests {
    @Test("PNG round-trip preserves dimensions and color space identifier")
    func pngRoundtrip() throws {
        let src = try makeImage(width: 24, height: 17, p3: false)
        let opts = SaveOptions()
        let data = try encode(src, format: .png, options: opts)
        let buffer = try ImageBuffer.decode(from: data)
        #expect(buffer.width == 24)
        #expect(buffer.height == 17)
        #expect(buffer.colorSpace?.name != nil)
    }

    @Test("JPEG round-trip preserves dimensions")
    func jpegRoundtrip() throws {
        let src = try makeImage(width: 32, height: 32, p3: false)
        var opts = SaveOptions()
        opts.jpegQuality = 0.85
        let data = try encode(src, format: .jpeg, options: opts)
        let buffer = try ImageBuffer.decode(from: data)
        #expect(buffer.width == 32)
        #expect(buffer.height == 32)
    }

    @Test("PNG round-trip preserves a Display P3 color space")
    func pngRoundtripPreservesP3() throws {
        let src = try makeImage(width: 16, height: 16, p3: true)
        // The source image was constructed with the Display P3 color space; it
        // should survive a PNG encode/decode cycle.
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        #expect(src.colorSpace?.name == p3.name)
        let data = try encode(src, format: .png, options: SaveOptions())
        let buffer = try ImageBuffer.decode(from: data)
        #expect(buffer.colorSpace?.name == p3.name)
    }

    @Test("JPEG quality is honored")
    func jpegQualityChangesSize() throws {
        let src = try makeImage(width: 64, height: 64, p3: false)
        var loQ = SaveOptions()
        loQ.jpegQuality = 0.10
        var hiQ = SaveOptions()
        hiQ.jpegQuality = 0.95
        let lo = try encode(src, format: .jpeg, options: loQ)
        let hi = try encode(src, format: .jpeg, options: hiQ)
        #expect(lo.count < hi.count)
    }

    private func makeImage(width: Int, height: Int, p3: Bool) throws -> CGImage {
        let cs: CGColorSpace = {
            if p3 { return CGColorSpace(name: CGColorSpace.displayP3)! }
            return CGColorSpaceCreateDeviceRGB()
        }()
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
        // Stripey gradient — gives JPEG something nontrivial to compress.
        for y in 0..<height {
            for x in 0..<width {
                let r = CGFloat((x ^ y) & 0xFF) / 255
                ctx.setFillColor(
                    CGColor(red: r, green: 1 - r, blue: CGFloat(x) / CGFloat(width), alpha: 1)
                )
                ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return ctx.makeImage()!
    }
}
