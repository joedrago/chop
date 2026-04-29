import AppKit
import simd

/// Edge-pan support: while a drag is in progress and the cursor is near the
/// canvas edge, pan `view.center` toward that edge on a timer so more of the
/// image becomes visible. The most-recent drag event is re-delivered to the
/// active tool each tick so the in-progress operation (e.g. rect selection)
/// follows the new image-space cursor position.
extension CanvasView {
    fileprivate static var kAutoscrollTimerKey: UInt8 = 0
    fileprivate static var kAutoscrollEventKey: UInt8 = 0
    private static let autoscrollBand: CGFloat = 40
    private static let autoscrollSpeed: CGFloat = 1200  // points/sec at the edge
    private static let autoscrollHz: Double = 60.0

    fileprivate var autoscrollTimer: Timer? {
        get { objc_getAssociatedObject(self, &Self.kAutoscrollTimerKey) as? Timer }
        set {
            objc_setAssociatedObject(
                self,
                &Self.kAutoscrollTimerKey,
                newValue,
                .OBJC_ASSOCIATION_RETAIN
            )
        }
    }

    fileprivate var autoscrollEvent: NSEvent? {
        get { objc_getAssociatedObject(self, &Self.kAutoscrollEventKey) as? NSEvent }
        set {
            objc_setAssociatedObject(
                self,
                &Self.kAutoscrollEventKey,
                newValue,
                .OBJC_ASSOCIATION_RETAIN
            )
        }
    }

    /// Called from `mouseDragged` for tools that benefit from edge-panning.
    /// Starts the timer if the cursor is in/past the edge band; stops it
    /// otherwise.
    func updateAutoscroll(for event: NSEvent) {
        let (vx, vy) = autoscrollVelocity(for: event)
        if vx == 0 && vy == 0 {
            stopAutoscroll()
            return
        }
        autoscrollEvent = event
        if autoscrollTimer == nil {
            let timer = Timer(
                timeInterval: 1.0 / Self.autoscrollHz,
                repeats: true
            ) { [weak self] _ in
                Task { @MainActor in self?.tickAutoscroll() }
            }
            timer.tolerance = 0.005
            RunLoop.main.add(timer, forMode: .common)
            autoscrollTimer = timer
        }
    }

    func stopAutoscroll() {
        autoscrollTimer?.invalidate()
        autoscrollTimer = nil
        autoscrollEvent = nil
    }

    private func autoscrollVelocity(for event: NSEvent) -> (CGFloat, CGFloat) {
        let p = convert(event.locationInWindow, from: nil)
        // Image-space y is down-positive; AppKit NSView coords are y-up by
        // default. Convert so positive y means "toward bottom of the image".
        let yDown = bounds.height - p.y
        let band = Self.autoscrollBand
        let speed = Self.autoscrollSpeed

        func axis(_ pos: CGFloat, _ size: CGFloat) -> CGFloat {
            if pos < band {
                let t = min(max((band - pos) / band, 0), 1.5)
                return -t * speed
            } else if pos > size - band {
                let t = min(max((pos - (size - band)) / band, 0), 1.5)
                return t * speed
            }
            return 0
        }
        return (axis(p.x, bounds.width), axis(yDown, bounds.height))
    }

    private func tickAutoscroll() {
        guard let event = autoscrollEvent, let doc = document else { return }
        let (vx, vy) = autoscrollVelocity(for: event)
        if vx == 0 && vy == 0 {
            stopAutoscroll()
            return
        }
        let dt = CGFloat(1.0 / Self.autoscrollHz)
        let zoom = max(doc.view.zoom, 0.0001)
        // Velocity is in NSView points/sec. Convert to backing pixels via the
        // backing-scale factor (drawableSize is in backing pixels), then to
        // image pixels by dividing by zoom.
        let backingScale = convertToBacking(NSSize(width: 1, height: 1)).width
        let dxImg = Float(vx * dt * backingScale) / zoom
        let dyImg = Float(vy * dt * backingScale) / zoom

        applyClampedPan(dx: dxImg, dy: dyImg, doc: doc)
        documentDidChange()
        NotificationCenter.default.post(name: .chopViewDidChange, object: self)

        // Re-deliver the drag event so the active tool extends its operation
        // using the new image-space position under the (unchanged) cursor.
        if let ctx = toolContext() {
            activeTool().mouseDragged(event, ctx: ctx)
        }
    }

    /// Pan view.center by (dx, dy) image pixels, but only along axes where
    /// the image actually overflows the viewport — and clamped so we don't
    /// scroll past the edge of the image on either side.
    private func applyClampedPan(dx: Float, dy: Float, doc: Document) {
        let drawable = drawableSize
        let viewportW = Float(drawable.width)
        let viewportH = Float(drawable.height)
        let zoom = max(doc.view.zoom, 0.0001)
        let visW = viewportW / zoom
        let visH = viewportH / zoom
        let imgW = Float(doc.width)
        let imgH = Float(doc.height)

        if visW < imgW {
            let lo = visW * 0.5
            let hi = imgW - visW * 0.5
            doc.view.center.x = min(max(doc.view.center.x + dx, lo), hi)
        }
        if visH < imgH {
            let lo = visH * 0.5
            let hi = imgH - visH * 0.5
            doc.view.center.y = min(max(doc.view.center.y + dy, lo), hi)
        }
    }
}
