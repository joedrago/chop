import AppKit
import Foundation

/// Identifier for the active tool. Stored on the Document.
public enum ToolId: String, Hashable {
    case rectSelect
    case pan
    case zoom
}

/// Mutable per-event context handed to a tool. Tools never poke the document
/// directly — they construct Actions and ask the host to commit them.
@MainActor
struct ToolContext {
    weak var window: ChopWindowController?
    weak var canvas: CanvasView?
    var document: Document

    /// The NSDocument shim that owns the data model — the action commit site.
    var documentHost: ChopDocument? { window?.document as? ChopDocument }
}

/// All tools share this minimal protocol. v1 tools live in `Chop/Tools/`.
@MainActor
protocol Tool: AnyObject {
    var id: ToolId { get }
    var displayName: String { get }
    var cursor: NSCursor { get }

    func mouseDown(_ event: NSEvent, ctx: ToolContext)
    func mouseDragged(_ event: NSEvent, ctx: ToolContext)
    func mouseUp(_ event: NSEvent, ctx: ToolContext)
    func keyDown(_ event: NSEvent, ctx: ToolContext)
}
