import AppKit

/// Left sidebar with one button per registered tool (Phase 2 / 3).
@MainActor
final class ToolboxView: NSView {
    weak var document: Document?
    var onToolChanged: ((ToolId) -> Void)?

    private var buttons: [ToolId: NSButton] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
        ])

        for (id, label) in [
            (ToolId.rectSelect, "▭"),
            (ToolId.pan, "✋"),
            (ToolId.zoom, "🔍"),
        ] {
            let b = NSButton(title: label, target: self, action: #selector(toolPressed(_:)))
            b.bezelStyle = .smallSquare
            b.setButtonType(.toggle)
            b.tag = toolTag(id)
            b.toolTip = ToolRegistry.shared.tool(for: id).displayName
            buttons[id] = b
            stack.addArrangedSubview(b)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used; programmatic only.")
    }

    func refresh() {
        guard let doc = document else { return }
        for (id, btn) in buttons {
            btn.state = (id == doc.activeToolId) ? .on : .off
        }
    }

    @objc private func toolPressed(_ sender: NSButton) {
        guard let id = toolForTag(sender.tag) else { return }
        document?.activeToolId = id
        refresh()
        onToolChanged?(id)
    }

    private func toolTag(_ id: ToolId) -> Int {
        switch id {
        case .rectSelect: return 0
        case .pan: return 1
        case .zoom: return 2
        }
    }

    private func toolForTag(_ tag: Int) -> ToolId? {
        switch tag {
        case 0: return .rectSelect
        case 1: return .pan
        case 2: return .zoom
        default: return nil
        }
    }
}
