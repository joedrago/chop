import AppKit

/// A thin status bar above the bottom of the document window: zoom %, image
/// dimensions, cursor coords (Phase 2 / 3).
@MainActor
final class StatusBarView: NSView {
    private let zoomLabel: NSTextField
    private let dimsLabel: NSTextField
    private let cursorLabel: NSTextField

    weak var document: Document? {
        didSet { refresh() }
    }

    override init(frame frameRect: NSRect) {
        zoomLabel = StatusBarView.makeLabel()
        dimsLabel = StatusBarView.makeLabel()
        cursorLabel = StatusBarView.makeLabel()
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor

        let stack = NSStackView(views: [zoomLabel, dimsLabel, cursorLabel])
        stack.orientation = .horizontal
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used; programmatic only.")
    }

    func refresh() {
        guard let doc = document else {
            zoomLabel.stringValue = ""
            dimsLabel.stringValue = ""
            cursorLabel.stringValue = ""
            return
        }
        let pct = Int((doc.view.zoom * 100).rounded())
        zoomLabel.stringValue = "Zoom \(pct)%"
        dimsLabel.stringValue = "\(doc.width) × \(doc.height) px"
    }

    func updateCursor(image point: SIMD2<Float>?) {
        if let p = point {
            cursorLabel.stringValue = String(format: "(%d, %d)", Int(p.x), Int(p.y))
        } else {
            cursorLabel.stringValue = ""
        }
    }

    private static func makeLabel() -> NSTextField {
        let f = NSTextField(labelWithString: "")
        f.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        f.textColor = .secondaryLabelColor
        f.lineBreakMode = .byTruncatingMiddle
        return f
    }
}
