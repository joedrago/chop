import AppKit
import QuartzCore
import simd

/// CAShapeLayer overlay for the active selection.
@MainActor
final class MarchingAntsLayer: CALayer {
    private let dashed: CAShapeLayer = .init()

    override init() {
        super.init()
        configure()
    }

    override init(layer: Any) {
        super.init(layer: layer)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        // The shape layer is the actual ant-line; this CALayer is just a host.
        dashed.fillColor = nil
        dashed.strokeColor = NSColor.white.cgColor
        dashed.lineWidth = 1.0
        dashed.lineDashPattern = [4, 4]
        dashed.shadowColor = NSColor.black.cgColor
        dashed.shadowOffset = .zero
        dashed.shadowOpacity = 0.6
        dashed.shadowRadius = 0.5
        addSublayer(dashed)
    }

    func update(rectInScreen rect: CGRect?) {
        guard let rect = rect, !rect.isEmpty else {
            dashed.path = nil
            removeAntsAnimation()
            return
        }
        let path = CGPath(rect: rect, transform: nil)
        dashed.path = path
        addAntsAnimation()
    }

    private func addAntsAnimation() {
        if dashed.animation(forKey: "marching") != nil { return }
        let anim = CABasicAnimation(keyPath: "lineDashPhase")
        anim.fromValue = 0
        anim.toValue = -8
        anim.duration = 0.4
        anim.repeatCount = .infinity
        dashed.add(anim, forKey: "marching")
    }

    private func removeAntsAnimation() {
        dashed.removeAnimation(forKey: "marching")
    }
}
