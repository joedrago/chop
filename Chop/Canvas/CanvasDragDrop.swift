import AppKit
import UniformTypeIdentifiers

/// Drag-and-drop file URLs onto the canvas → open in Chop.
extension CanvasView {
    func enableFileDrops() {
        registerForDraggedTypes([.fileURL])
    }

    public override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: urlOptions())
            ? .copy : []
    }

    public override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard
            let urls = sender.draggingPasteboard.readObjects(
                forClasses: [NSURL.self],
                options: urlOptions()
            ) as? [URL],
            !urls.isEmpty
        else {
            return false
        }
        let app = NSApp.delegate as? NSApplicationDelegate
        if let app = app {
            app.application?(NSApp, open: urls)
        } else {
            for url in urls {
                NSDocumentController.shared.openDocument(
                    withContentsOf: url,
                    display: true,
                    completionHandler: { _, _, _ in }
                )
            }
        }
        return true
    }

    private func urlOptions() -> [NSPasteboard.ReadingOptionKey: Any] {
        let imageTypes = NSImage.imageTypes
        return [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: imageTypes,
        ]
    }
}
