import AppKit

/// Modal sheet shown after NSSavePanel returns, for format-specific encoder
/// knobs.
@MainActor
final class SaveOptionsSheet: NSWindowController {
    let format: SaveOptions.Format
    private(set) var options = SaveOptions()
    var onCommit: ((SaveOptions) -> Void)?

    init(format: SaveOptions.Format) {
        self.format = format
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Save Options — \(format == .png ? "PNG" : "JPEG")"
        super.init(window: panel)
        layout(in: panel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used; programmatic only.")
    }

    func runModalSheet(on parent: NSWindow) {
        guard let panel = window else { return }
        parent.beginSheet(panel) { _ in }
    }

    private func layout(in panel: NSPanel) {
        guard let content = panel.contentView else { return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        switch format {
        case .png:
            let interlaced = NSButton(
                checkboxWithTitle: "Interlaced",
                target: self,
                action: #selector(togglePNGInterlaced(_:))
            )
            interlaced.state = options.pngInterlaced ? .on : .off
            stack.addArrangedSubview(interlaced)
        case .jpeg:
            let qualityRow = NSStackView()
            qualityRow.orientation = .horizontal
            qualityRow.spacing = 8
            let label = NSTextField(labelWithString: "Quality:")
            let slider = NSSlider(
                value: options.jpegQuality,
                minValue: 0.05,
                maxValue: 1.0,
                target: self,
                action: #selector(qualityChanged(_:))
            )
            slider.numberOfTickMarks = 11
            slider.allowsTickMarkValuesOnly = false
            slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
            let value = NSTextField(labelWithString: percentString(options.jpegQuality))
            value.identifier = NSUserInterfaceItemIdentifier("qualityValue")
            value.widthAnchor.constraint(equalToConstant: 40).isActive = true
            qualityRow.addArrangedSubview(label)
            qualityRow.addArrangedSubview(slider)
            qualityRow.addArrangedSubview(value)
            stack.addArrangedSubview(qualityRow)

            let progressive = NSButton(
                checkboxWithTitle: "Progressive",
                target: self,
                action: #selector(toggleJPEGProgressive(_:))
            )
            progressive.state = options.jpegProgressive ? .on : .off
            stack.addArrangedSubview(progressive)
        }

        let cancelBtn = NSButton(
            title: "Cancel",
            target: self,
            action: #selector(cancel(_:))
        )
        let okBtn = NSButton(
            title: "Save",
            target: self,
            action: #selector(commit(_:))
        )
        okBtn.keyEquivalent = "\r"
        let buttons = NSStackView(views: [cancelBtn, okBtn])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        stack.addArrangedSubview(buttons)

        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    @objc private func togglePNGInterlaced(_ sender: NSButton) {
        options.pngInterlaced = (sender.state == .on)
    }

    @objc private func toggleJPEGProgressive(_ sender: NSButton) {
        options.jpegProgressive = (sender.state == .on)
    }

    @objc private func qualityChanged(_ sender: NSSlider) {
        options.jpegQuality = sender.doubleValue
        guard let view = window?.contentView else { return }
        if let label = view.findFirst(byID: "qualityValue") as? NSTextField {
            label.stringValue = percentString(options.jpegQuality)
        }
    }

    @objc private func cancel(_ sender: Any?) {
        guard let panel = window else { return }
        panel.sheetParent?.endSheet(panel, returnCode: .cancel)
    }

    @objc private func commit(_ sender: Any?) {
        guard let panel = window else { return }
        onCommit?(options)
        panel.sheetParent?.endSheet(panel, returnCode: .OK)
    }

    private func percentString(_ q: Double) -> String {
        "\(Int((q * 100).rounded()))%"
    }
}

extension NSView {
    fileprivate func findFirst(byID id: String) -> NSView? {
        if self.identifier?.rawValue == id { return self }
        for sub in subviews {
            if let v = sub.findFirst(byID: id) { return v }
        }
        return nil
    }
}
