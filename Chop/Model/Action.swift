import Foundation

/// All edits flow through Actions. The NSDocument subclass commits them and
/// registers undo/redo with NSUndoManager.
@MainActor
public protocol Action {
    /// Shown in Edit ▸ Undo X / Redo X.
    var label: String { get }
    func apply(to document: Document) throws
    func revert(from document: Document) throws
}
