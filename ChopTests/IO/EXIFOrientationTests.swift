import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Chop

@Suite("EXIF Orientation")
struct EXIFOrientationTests {
    @Test("Right (6) orientation swaps axes")
    func rightSwapsAxes() throws {
        // Build a 4×2 image with EXIF Orientation=6 (right). After applying,
        // the result should be 2×4.
        let data = try synthesizeWithOrientation(width: 4, height: 2, exifOrientation: 6)
        let buffer = try ImageBuffer.decode(from: data)
        #expect(buffer.width == 2)
        #expect(buffer.height == 4)
    }

    @Test("Up (1) orientation passes through unchanged")
    func upUnchanged() throws {
        let data = try synthesizeWithOrientation(width: 4, height: 2, exifOrientation: 1)
        let buffer = try ImageBuffer.decode(from: data)
        #expect(buffer.width == 4)
        #expect(buffer.height == 2)
    }

    private func synthesizeWithOrientation(
        width: Int,
        height: Int,
        exifOrientation: Int
    ) throws -> Data {
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard
            let ctx = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: cs,
                bitmapInfo: info.rawValue
            )
        else {
            Issue.record("Failed to create CGContext.")
            return Data()
        }
        // Make a horizontal stripe for visual checkability.
        ctx.setFillColor(CGColor(red: 0, green: 0.6, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = ctx.makeImage() else {
            Issue.record("Failed to create CGImage.")
            return Data()
        }
        let mut = NSMutableData()
        guard
            let dest = CGImageDestinationCreateWithData(
                mut,
                UTType.tiff.identifier as CFString,
                1,
                nil
            )
        else {
            Issue.record("Failed to create CGImageDestination.")
            return Data()
        }
        let props: [CFString: Any] = [kCGImagePropertyOrientation: exifOrientation]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
        return mut as Data
    }
}
