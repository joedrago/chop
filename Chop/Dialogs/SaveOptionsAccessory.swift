import AppKit

/// Accessory view attached to the NSSavePanel via `prepareSavePanel(_:)`.
/// Updates a `SaveOptions` value bound by the document.
@MainActor
final class SaveOptionsAccessoryView: NSView {
    let format: SaveOptions.Format
    var options: SaveOptions {
        didSet { onChange?(options) }
    }
    var onChange: ((SaveOptions) -> Void)?

    private var qualityLabel: NSTextField?

    init(format: SaveOptions.Format, options: SaveOptions) {
        self.format = format
        self.options = options
        super.init(frame: .zero)
        installSubviews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used; programmatic only.")
    }

    private func installSubviews() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
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
            slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
            let value = NSTextField(labelWithString: percentString(options.jpegQuality))
            value.widthAnchor.constraint(equalToConstant: 40).isActive = true
            qualityLabel = value
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

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
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
        qualityLabel?.stringValue = percentString(options.jpegQuality)
    }

    private func percentString(_ q: Double) -> String {
        "\(Int((q * 100).rounded()))%"
    }
}
