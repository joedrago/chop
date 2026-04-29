import CoreGraphics
import Foundation
import Testing

@testable import Chop

@MainActor
@Suite("CropAction")
struct CropActionTests {
    @Test("Crops dimensions and updates layer pixels")
    func cropChangesDimensions() throws {
        let doc = try makeColoredDoc(width: 32, height: 32)
        let action = CropAction(rect: IRect(x: 8, y: 8, width: 16, height: 16))
        try action.apply(to: doc)
        #expect(doc.width == 16)
        #expect(doc.height == 16)
        #expect(doc.layers[0].pixels.cgImage.width == 16)
        #expect(doc.layers[0].pixels.cgImage.height == 16)
    }

    @Test("Revert restores prior dimensions, pixels, selection")
    func revertRestores() throws {
        let doc = try makeColoredDoc(width: 32, height: 32)
        doc.selection = .rect(IRect(x: 0, y: 0, width: 4, height: 4))
        let priorBytes = imageBytes(doc.composite())
        let action = CropAction(rect: IRect(x: 8, y: 8, width: 16, height: 16))
        try action.apply(to: doc)
        try action.revert(from: doc)
        #expect(doc.width == 32)
        #expect(doc.height == 32)
        #expect(doc.layers[0].pixels.cgImage.width == 32)
        #expect(doc.composite().width == 32)
        let afterBytes = imageBytes(doc.composite())
        #expect(priorBytes == afterBytes)
        if case .rect(let r) = doc.selection {
            #expect(r.width == 4 && r.height == 4)
        } else {
            Issue.record("Expected selection to be restored.")
        }
    }

    @Test("Empty crop rect throws")
    func emptyThrows() throws {
        let doc = try makeColoredDoc(width: 16, height: 16)
        let action = CropAction(rect: IRect(x: 0, y: 0, width: 0, height: 0))
        #expect(throws: ChopError.self) {
            try action.apply(to: doc)
        }
    }

    @Test(
        "Fuzz: random apply / revert sequences are idempotent",
        arguments: [42, 1337, 9001, 7, 65535]
    )
    func fuzz(seed: UInt32) throws {
        var rng = SeededRNG(state: UInt64(seed) | 1)
        let doc = try makeColoredDoc(width: 64, height: 64)
        let originalBytes = imageBytes(doc.composite())
        var stack: [CropAction] = []
        for _ in 0..<8 {
            // Random crop within current document.
            let w = max(1, Int(rng.nextBounded(UInt32(doc.width))))
            let h = max(1, Int(rng.nextBounded(UInt32(doc.height))))
            let x = Int(rng.nextBounded(UInt32(doc.width - w + 1)))
            let y = Int(rng.nextBounded(UInt32(doc.height - h + 1)))
            let rect = IRect(x: x, y: y, width: w, height: h)
            let act = CropAction(rect: rect)
            try act.apply(to: doc)
            stack.append(act)
        }
        // Revert in reverse order — should land back at the original.
        while let act = stack.popLast() {
            try act.revert(from: doc)
        }
        #expect(doc.width == 64)
        #expect(doc.height == 64)
        #expect(imageBytes(doc.composite()) == originalBytes)
    }

    private func makeColoredDoc(width: Int, height: Int) throws -> Document {
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
        // Paint a gradient so we can compare bytes.
        for y in 0..<height {
            for x in 0..<width {
                let r = CGFloat(x) / CGFloat(max(1, width - 1))
                let g = CGFloat(y) / CGFloat(max(1, height - 1))
                ctx.setFillColor(CGColor(red: r, green: g, blue: 0.5, alpha: 1))
                ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        let img = ctx.makeImage()!
        return Document.fromImage(img)
    }

    private func imageBytes(_ image: CGImage) -> Data {
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let bytes = image.width * image.height * 4
        var data = Data(count: bytes)
        data.withUnsafeMutableBytes { raw in
            let ctx = CGContext(
                data: raw.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: cs,
                bitmapInfo: info.rawValue
            )
            ctx?.draw(
                image,
                in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
            )
        }
        return data
    }
}

/// Deterministic xorshift64 RNG so tests don't depend on the platform RNG.
private struct SeededRNG {
    var state: UInt64

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func nextBounded(_ bound: UInt32) -> UInt32 {
        if bound == 0 { return 0 }
        return UInt32(next() & 0xFFFF_FFFF) % bound
    }
}
