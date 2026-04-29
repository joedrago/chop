import AppKit
import CoreGraphics
import UniformTypeIdentifiers

/// File ▸ New from Clipboard / Selection. Lives on AppDelegate so the
/// "from Clipboard" form is reachable even when no document is open.
extension AppDelegate {
    @objc func newFromClipboard(_ sender: Any?) {
        guard let image = Self.clipboardCGImage() else {
            NSSound.beep()
            return
        }
        present(ChopDocument.newUntitled(from: image))
    }

    @objc func newFromSelection(_ sender: Any?) {
        guard
            let source = NSDocumentController.shared.currentDocument as? ChopDocument,
            let model = source.model,
            case .rect(let r) = model.selection
        else {
            NSSound.beep()
            return
        }
        let clamped = r.clamped(toImageWidth: model.width, height: model.height)
        guard !clamped.isEmpty else {
            NSSound.beep()
            return
        }
        let cropRect = CGRect(
            x: clamped.x,
            y: clamped.y,
            width: clamped.width,
            height: clamped.height
        )
        guard let cropped = model.composite().cropping(to: cropRect) else {
            NSSound.beep()
            return
        }
        // .cropping(to:) lazily references the source's pixel storage. Realize
        // it into its own backing so the new document doesn't pin the parent.
        let realized = Self.realize(cropped)
        present(ChopDocument.newUntitled(from: realized))
    }

    private func present(_ doc: ChopDocument) {
        NSDocumentController.shared.addDocument(doc)
        doc.makeWindowControllers()
        doc.showWindows()
    }

    /// Read the first image-conforming pasteboard item as a CGImage, decoding
    /// via ImageIO so the source color space is preserved. Returns nil when
    /// the clipboard has no image.
    static func clipboardCGImage() -> CGImage? {
        let pb = NSPasteboard.general
        guard let types = pb.types else { return nil }
        for t in types {
            guard let utt = UTType(t.rawValue), utt.conforms(to: .image) else { continue }
            guard let data = pb.data(forType: t) else { continue }
            if let buffer = try? ImageBuffer.decode(from: data) {
                return buffer.cgImage
            }
        }
        return nil
    }

    /// Force-render `image` into its own backing store (preserving color
    /// space) to detach it from any shared parent storage from
    /// `CGImage.cropping(to:)`.
    static func realize(_ image: CGImage) -> CGImage {
        let cs = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard
            let ctx = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: cs,
                bitmapInfo: info.rawValue
            )
        else {
            return image
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage() ?? image
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(newFromClipboard(_:)):
            return Self.clipboardCGImage() != nil
        case #selector(newFromSelection(_:)):
            guard
                let doc = NSDocumentController.shared.currentDocument as? ChopDocument,
                let model = doc.model,
                case .rect(let r) = model.selection
            else { return false }
            return !r.clamped(toImageWidth: model.width, height: model.height).isEmpty
        default:
            return true
        }
    }
}
