import Foundation

/// Replaces the document's selection. Reverts by restoring the prior value.
@MainActor
final class SetSelectionAction: Action {
    let label: String = "Selection"
    let priorSelection: Selection
    let newSelection: Selection

    init(prior: Selection, new: Selection) {
        self.priorSelection = prior
        self.newSelection = new
    }

    func apply(to document: Document) throws {
        document.selection = newSelection
    }

    func revert(from document: Document) throws {
        document.selection = priorSelection
    }
}
