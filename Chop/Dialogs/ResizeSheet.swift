import AppKit

/// Modal sheet for Image ▸ Resize. Pixel-mode width/height OR
/// percentage-mode inputs, lock-aspect toggle, filter dropdown, live preview.
@MainActor
final class ResizeSheet: NSWindowController, NSTextFieldDelegate {
    private let originalWidth: Int
    private let originalHeight: Int
    private var lockedAspect: Bool = true

    private let modePixels: NSButton
    private let modePercent: NSButton
    private let widthField: NSTextField
    private let heightField: NSTextField
    private let lockToggle: NSButton
    private let filterPopup: NSPopUpButton
    private let preview: NSTextField

    var onCommit: ((Int, Int, ResampleFilter) -> Void)?

    init(originalWidth: Int, originalHeight: Int) {
        self.originalWidth = originalWidth
        self.originalHeight = originalHeight

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Resize"

        modePixels = NSButton(
            radioButtonWithTitle: "Pixels",
            target: nil,
            action: nil
        )
        modePercent = NSButton(
            radioButtonWithTitle: "Percent",
            target: nil,
            action: nil
        )
        widthField = NSTextField()
        widthField.alignment = .right
        widthField.formatter = ResizeSheet.numberFormatter()
        widthField.stringValue = String(originalWidth)
        heightField = NSTextField()
        heightField.alignment = .right
        heightField.formatter = ResizeSheet.numberFormatter()
        heightField.stringValue = String(originalHeight)
        lockToggle = NSButton(checkboxWithTitle: "Lock aspect ratio", target: nil, action: nil)
        lockToggle.state = .on

        filterPopup = NSPopUpButton()
        for f in ResampleFilter.allCases {
            filterPopup.addItem(withTitle: f.displayName)
            filterPopup.lastItem?.representedObject = f
        }
        filterPopup.selectItem(at: 1)  // Bilinear default

        preview = NSTextField(labelWithString: "")
        preview.font = .monospacedDigitSystemFont(
            ofSize: NSFont.smallSystemFontSize,
            weight: .regular
        )
        preview.textColor = .secondaryLabelColor

        super.init(window: panel)

        modePixels.target = self
        modePercent.target = self
        modePixels.action = #selector(modeChanged(_:))
        modePercent.action = #selector(modeChanged(_:))
        modePixels.state = .on

        lockToggle.target = self
        lockToggle.action = #selector(lockChanged(_:))

        widthField.delegate = self
        heightField.delegate = self

        layout(in: panel)
        refreshPreview()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used; programmatic only.")
    }

    func runModalSheet(on parent: NSWindow) {
        guard let panel = window else { return }
        parent.beginSheet(panel) { _ in }
    }

    // MARK: - Layout

    private func layout(in panel: NSPanel) {
        guard let content = panel.contentView else { return }

        let modeRow = NSStackView(views: [modePixels, modePercent])
        modeRow.orientation = .horizontal
        modeRow.spacing = 12

        widthField.widthAnchor.constraint(equalToConstant: 100).isActive = true
        heightField.widthAnchor.constraint(equalToConstant: 100).isActive = true

        let widthLabel = NSTextField(labelWithString: "Width:")
        let heightLabel = NSTextField(labelWithString: "Height:")
        let filterLabel = NSTextField(labelWithString: "Filter:")

        // Grid keeps label column right-aligned and control column
        // left-aligned, instead of the ragged-edge look of stacked rows.
        let formGrid = NSGridView(views: [
            [widthLabel, widthField],
            [heightLabel, heightField],
            [NSGridCell.emptyContentView, lockToggle],
            [filterLabel, filterPopup],
        ])
        formGrid.column(at: 0).xPlacement = .trailing
        formGrid.column(at: 1).xPlacement = .leading
        formGrid.rowSpacing = 8
        formGrid.columnSpacing = 8

        let cancelButton = NSButton(
            title: "Cancel",
            target: self,
            action: #selector(cancel(_:))
        )
        cancelButton.keyEquivalent = "\u{1b}"
        let okButton = NSButton(
            title: "OK",
            target: self,
            action: #selector(commit(_:))
        )
        okButton.keyEquivalent = "\r"
        let buttonRow = NSStackView(views: [cancelButton, okButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8

        let stack = NSStackView(views: [
            modeRow,
            formGrid,
            preview,
            buttonRow,
        ])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        let margin: CGFloat = 20
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: margin),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -margin),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: margin),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -margin),
        ])

        // Shrink the fixed (non-resizable) panel to its content's natural size.
        panel.layoutIfNeeded()
        let fitting = stack.fittingSize
        panel.setContentSize(
            NSSize(
                width: fitting.width + margin * 2,
                height: fitting.height + margin * 2
            )
        )
    }

    // MARK: - Buttons

    @objc private func cancel(_ sender: Any?) {
        guard let panel = window else { return }
        panel.sheetParent?.endSheet(panel, returnCode: .cancel)
    }

    @objc private func commit(_ sender: Any?) {
        guard let panel = window else { return }
        let (w, h) = currentPixelSize()
        guard w > 0, h > 0 else {
            NSSound.beep()
            return
        }
        let filter =
            (filterPopup.selectedItem?.representedObject as? ResampleFilter)
            ?? .bilinear
        onCommit?(w, h, filter)
        panel.sheetParent?.endSheet(panel, returnCode: .OK)
    }

    @objc private func modeChanged(_ sender: NSButton) {
        if sender == modePixels {
            modePercent.state = .off
            widthField.stringValue = String(originalWidth)
            heightField.stringValue = String(originalHeight)
        } else {
            modePixels.state = .off
            widthField.stringValue = "100"
            heightField.stringValue = "100"
        }
        refreshPreview()
    }

    @objc private func lockChanged(_ sender: NSButton) {
        lockedAspect = (sender.state == .on)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        guard lockedAspect else {
            refreshPreview()
            return
        }
        let aspect = Double(originalWidth) / Double(originalHeight)
        if field === widthField, let newW = Double(field.stringValue) {
            if isPixelMode {
                heightField.stringValue = String(Int((newW / aspect).rounded()))
            } else {
                heightField.stringValue = String(Int(newW.rounded()))
            }
        } else if field === heightField, let newH = Double(field.stringValue) {
            if isPixelMode {
                widthField.stringValue = String(Int((newH * aspect).rounded()))
            } else {
                widthField.stringValue = String(Int(newH.rounded()))
            }
        }
        refreshPreview()
    }

    // MARK: - State

    private var isPixelMode: Bool { modePixels.state == .on }

    private func currentPixelSize() -> (Int, Int) {
        let wv = (widthField.stringValue as NSString).integerValue
        let hv = (heightField.stringValue as NSString).integerValue
        if isPixelMode {
            return (max(0, wv), max(0, hv))
        }
        let pw = Double(originalWidth) * Double(wv) / 100
        let ph = Double(originalHeight) * Double(hv) / 100
        return (max(0, Int(pw.rounded())), max(0, Int(ph.rounded())))
    }

    private func refreshPreview() {
        let (w, h) = currentPixelSize()
        if w <= 0 || h <= 0 {
            preview.stringValue = "Invalid dimensions"
            return
        }
        let mp = Double(w) * Double(h) / 1_000_000
        preview.stringValue = String(format: "→ %d × %d  (%.2f MP)", w, h, mp)
    }

    private static func numberFormatter() -> NumberFormatter {
        let f = NumberFormatter()
        f.minimum = 1
        f.maximum = 65535
        f.allowsFloats = false
        return f
    }
}
