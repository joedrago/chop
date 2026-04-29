import CoreGraphics
import simd

/// Integer-aligned, image-space rectangle (PLAN.md §4).
public struct IRect: Equatable, Hashable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var isEmpty: Bool { width <= 0 || height <= 0 }

    public var minX: Int { x }
    public var minY: Int { y }
    public var maxX: Int { x + width }
    public var maxY: Int { y + height }

    public var cgRect: CGRect {
        CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
    }

    /// Clamp this rect to the bounds (0,0,width,height) of an image, returning
    /// the intersection. Empty if there is no overlap.
    public func clamped(toImageWidth w: Int, height h: Int) -> IRect {
        let lo = (x: max(0, x), y: max(0, y))
        let hi = (x: min(w, maxX), y: min(h, maxY))
        return IRect(x: lo.x, y: lo.y, width: max(0, hi.x - lo.x), height: max(0, hi.y - lo.y))
    }

    public static func fromTwoPoints(_ a: (x: Int, y: Int), _ b: (x: Int, y: Int)) -> IRect {
        let lo = (x: min(a.x, b.x), y: min(a.y, b.y))
        let hi = (x: max(a.x, b.x), y: max(a.y, b.y))
        return IRect(x: lo.x, y: lo.y, width: hi.x - lo.x, height: hi.y - lo.y)
    }
}
