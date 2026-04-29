import CoreGraphics
import Foundation
import Testing

@testable import Chop

@MainActor
@Suite("Selection / SetSelectionAction")
struct SelectionTests {
    @Test("Selection.rect with empty rect is reported inactive")
    func inactiveWhenEmpty() {
        let s: Selection = .rect(IRect(x: 0, y: 0, width: 0, height: 0))
        #expect(!s.isActive)
    }

    @Test("Apply / revert restores prior selection")
    func applyRevert() throws {
        let doc = try makeOnePixelDoc()
        doc.selection = .none
        let action = SetSelectionAction(
            prior: .none,
            new: .rect(IRect(x: 0, y: 0, width: 4, height: 4))
        )
        try action.apply(to: doc)
        #expect(doc.selection.isActive)
        try action.revert(from: doc)
        if case .none = doc.selection {
        } else {
            Issue.record("Expected .none after revert, got \(doc.selection)")
        }
    }

    private func makeOnePixelDoc() throws -> Document {
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let ctx = CGContext(
            data: nil,
            width: 4,
            height: 4,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: info.rawValue
        )!
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let img = ctx.makeImage()!
        return Document.fromImage(img)
    }
}
