import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Chop

@Suite("ImageIO round-trip / PNG")
struct RoundtripPNGTests {
    @Test("Decode a simple RGB PNG")
    func decodePNG() throws {
        let data = try synthesizePNG(width: 4, height: 3)
        let buffer = try ImageBuffer.decode(from: data)
        #expect(buffer.width == 4)
        #expect(buffer.height == 3)
        #expect(buffer.colorSpace != nil)
    }

    @Test("Document.fromImage produces a single-layer document")
    func fromImage() throws {
        let data = try synthesizePNG(width: 8, height: 8)
        let buffer = try ImageBuffer.decode(from: data)
        let doc = Document.fromImage(buffer.cgImage)
        #expect(doc.width == 8)
        #expect(doc.height == 8)
        #expect(doc.layers.count == 1)
        #expect(doc.layers[0].name == "Background")
        #expect(doc.layers[0].opacity == 1.0)
        #expect(doc.layers[0].visible)
    }

    private func synthesizePNG(width: Int, height: Int) throws -> Data {
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
        ctx.setFillColor(CGColor(red: 1, green: 0.5, blue: 0.25, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = ctx.makeImage() else {
            Issue.record("Failed to create CGImage.")
            return Data()
        }
        let mut = NSMutableData()
        guard
            let dest = CGImageDestinationCreateWithData(
                mut,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else {
            Issue.record("Failed to create CGImageDestination.")
            return Data()
        }
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        return mut as Data
    }
}
