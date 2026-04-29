import AppKit
import ImageIO
import UniformTypeIdentifiers

/// AppKit shim that wraps the pure-Swift `Model.Document`.
final class ChopDocument: NSDocument {
    /// The pure-Swift data model. Set during `read(from:ofType:)`; never nil
    /// once a document has been opened.
    private(set) var model: Document?

    override init() {
        super.init()
        chopLog("ChopDocument init")
    }

    override class var autosavesInPlace: Bool {
        false
    }

    override func makeWindowControllers() {
        chopLog("makeWindowControllers (hasModel=\(self.model != nil))")
        let controller = ChopWindowController(document: self)
        addWindowController(controller)
        chopLog(
            "makeWindowControllers done; hasWindow=\(controller.window != nil) "
                + "frame=\(String(describing: controller.window?.frame))"
        )
    }

    /// Build an untitled document around an already-decoded `CGImage`. Used by
    /// File ▸ New from Clipboard / Selection. The doc is marked dirty so closing
    /// without saving prompts, and `fileType` defaults to PNG so the standard
    /// save flow has a writable type to fall back on.
    static func newUntitled(from image: CGImage) -> ChopDocument {
        let doc = ChopDocument()
        doc.model = Document.fromImage(image)
        doc.fileType = "public.png"
        doc.updateChangeCount(.changeDone)
        return doc
    }

    override func read(from data: Data, ofType typeName: String) throws {
        chopLog("read(from:ofType:\(typeName)) byteCount=\(data.count)")
        do {
            let buffer = try ImageBuffer.decode(from: data)
            self.model = Document.fromImage(buffer.cgImage)
            chopLog(
                "read OK: \(buffer.width)x\(buffer.height) "
                    + "cs=\(String(describing: buffer.colorSpace?.name))"
            )
        } catch {
            chopLog("read FAILED: \(error)")
            throw error
        }
    }

    override func showWindows() {
        chopLog("showWindows; controllers=\(self.windowControllers.count)")
        super.showWindows()
        for case let wc as ChopWindowController in windowControllers {
            chopLog(
                "  controller window visible=\(wc.window?.isVisible ?? false) "
                    + "frame=\(String(describing: wc.window?.frame))"
            )
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        guard let model = self.model else {
            throw ChopError.encodeFailed
        }
        guard let format = SaveOptions.Format(uti: typeName) else {
            throw ChopError.unsupportedType(typeName)
        }
        let options = pendingSaveOptions ?? SaveOptions()
        return try encode(model.flatten(), format: format, options: options)
    }

    /// Save Options accessory → data(ofType:) hand-off. NSDocument's save
    /// flow invokes data(ofType:) on the same call stack as
    /// `runModalSavePanel`, so we stash the chosen options briefly here.
    var pendingSaveOptions: SaveOptions?

    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        let format = inferSaveFormat(from: savePanel)
        let accessory = SaveOptionsAccessoryView(format: format, options: SaveOptions())
        accessory.onChange = { [weak self] opts in
            self?.pendingSaveOptions = opts
        }
        pendingSaveOptions = accessory.options
        savePanel.accessoryView = accessory
        return super.prepareSavePanel(savePanel)
    }

    private func inferSaveFormat(from panel: NSSavePanel) -> SaveOptions.Format {
        // The save panel may not have a format yet; use the document's current
        // type if available, falling back to PNG.
        if let typeName = self.fileType,
            let format = SaveOptions.Format(uti: typeName)
        {
            return format
        }
        return .png
    }

    override class var readableTypes: [String] {
        ["public.png", "public.jpeg"]
    }

    override class var writableTypes: [String] {
        ["public.png", "public.jpeg"]
    }

    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool {
        true
    }

    override class func isNativeType(_ type: String) -> Bool {
        type == "public.png" || type == "public.jpeg"
    }

    override func fileNameExtension(
        forType typeName: String,
        saveOperation: NSDocument.SaveOperationType
    ) -> String? {
        SaveOptions.Format(uti: typeName)?.defaultExtension
    }
}
