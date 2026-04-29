import Foundation
import Testing

@testable import Chop

@Suite("Geometry / IRect")
struct GeometryTests {
    @Test("Zero-size rect is empty")
    func emptyRect() {
        #expect(IRect(x: 0, y: 0, width: 0, height: 5).isEmpty)
        #expect(IRect(x: 0, y: 0, width: 5, height: 0).isEmpty)
        #expect(!IRect(x: 0, y: 0, width: 1, height: 1).isEmpty)
    }

    @Test("fromTwoPoints normalizes order")
    func twoPoints() {
        let r = IRect.fromTwoPoints((10, 20), (5, 8))
        #expect(r.x == 5 && r.y == 8 && r.width == 5 && r.height == 12)
    }

    @Test("clamped intersects with image bounds")
    func clamped() {
        let r = IRect(x: -3, y: -2, width: 10, height: 10)
        let c = r.clamped(toImageWidth: 5, height: 5)
        #expect(c.x == 0 && c.y == 0 && c.width == 5 && c.height == 5)
    }

    @Test("clamped is empty when outside")
    func clampedOutside() {
        let r = IRect(x: 100, y: 100, width: 5, height: 5)
        let c = r.clamped(toImageWidth: 50, height: 50)
        #expect(c.isEmpty)
    }
}
