import AppKit

/// Right sidebar — surfaces cursor position and selection rect.
@MainActor
final class InfoPaletteView: NSView {
    weak var document: Document?

    private let cursorRow: NSTextField
    private let selectionOriginRow: NSTextField
    private let selectionSizeRow: NSTextField

    override init(frame frameRect: NSRect) {
        let title = NSTextField(labelWithString: "Info")
        title.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false

        cursorRow = InfoPaletteView.makeRow()
        selectionOriginRow = InfoPaletteView.makeRow()
        selectionSizeRow = InfoPaletteView.makeRow()

        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor

        let stack = NSStackView(views: [
            title, cursorRow, selectionOriginRow, selectionSizeRow,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
        ])
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used; programmatic only.")
    }

    /// Live cursor position in image-space pixels. Pass `nil` to clear (mouse
    /// has left the canvas). Coordinates are clamped to the image's pixel
    /// bounds so they never read negative or beyond the image.
    func updateCursor(image point: SIMD2<Float>?) {
        guard let p = point, let doc = document else {
            cursorRow.stringValue = "Cursor: —"
            return
        }
        let x = clamp(Int(p.x.rounded(.down)), lo: 0, hi: max(doc.width - 1, 0))
        let y = clamp(Int(p.y.rounded(.down)), lo: 0, hi: max(doc.height - 1, 0))
        cursorRow.stringValue = String(format: "Cursor: %d, %d", x, y)
    }

    /// Repopulate from the document's current selection.
    func refresh() {
        guard let doc = document else {
            cursorRow.stringValue = "Cursor: —"
            selectionOriginRow.stringValue = "Selection: —"
            selectionSizeRow.stringValue = ""
            return
        }
        switch doc.selection {
        case .none:
            selectionOriginRow.stringValue = "Selection: —"
            selectionSizeRow.stringValue = ""
        case .rect(let r):
            selectionOriginRow.stringValue = "Selection: \(r.x), \(r.y)"
            selectionSizeRow.stringValue = "Size: \(r.width) × \(r.height)"
        }
    }

    private static func makeRow() -> NSTextField {
        let f = NSTextField(labelWithString: "")
        f.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        f.textColor = .secondaryLabelColor
        return f
    }
}

private func clamp(_ v: Int, lo: Int, hi: Int) -> Int {
    min(max(v, lo), hi)
}
