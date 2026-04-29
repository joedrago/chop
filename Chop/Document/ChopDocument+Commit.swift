import AppKit

/// Action commit + undo wiring (PLAN.md §7). Stays as a thin layer over
/// NSUndoManager so Edit ▸ Undo/Redo dynamic labels come for free.
extension ChopDocument {
    /// Apply an action and register undo/redo with NSUndoManager.
    /// Pre-condition: `model` is non-nil (i.e. a document has been opened).
    func commit(_ action: any Action) {
        guard let model = self.model else {
            chopLog("commit() called with no model loaded.")
            return
        }
        do {
            try action.apply(to: model)
        } catch {
            chopLog("Action apply failed: \(error)")
            return
        }
        registerUndo(of: action)
        updateChangeCount(.changeDone)
        notifyWindowsOfModelChange()
    }

    /// Bookkeeping: register undo (and the redo-of-undo) for `action`.
    private func registerUndo(of action: any Action) {
        guard let undo = undoManager else { return }
        let actionLabel = action.label
        undo.setActionName(actionLabel)
        undo.registerUndo(withTarget: self) { target in
            guard let model = target.model else { return }
            do {
                try action.revert(from: model)
                target.updateChangeCount(.changeUndone)
                target.notifyWindowsOfModelChange()
            } catch {
                chopLog("Action revert failed: \(error)")
            }
            // Register the redo (apply) as well, so the same action goes
            // forward and backward symmetrically.
            target.registerRedo(of: action)
        }
    }

    private func registerRedo(of action: any Action) {
        guard let undo = undoManager else { return }
        undo.registerUndo(withTarget: self) { target in
            target.commit(action)
        }
    }

    func notifyWindowsOfModelChange() {
        for case let wc as ChopWindowController in windowControllers {
            wc.documentDidUpdate()
        }
    }

    /// First-responder action: Edit ▸ Deselect (PLAN.md §9).
    @objc func deselect(_ sender: Any?) {
        guard let model = self.model else { return }
        if case .none = model.selection { return }
        commit(SetSelectionAction(prior: model.selection, new: .none))
    }

    /// First-responder action: File ▸ Save with overwrite confirmation.
    /// For first-save (no fileURL yet) this falls straight through to the
    /// standard save flow, which presents the save panel.
    @objc func saveWithConfirm(_ sender: Any?) {
        guard fileURL != nil else {
            save(sender)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Overwrite “\(displayName ?? "this file")”?"
        alert.informativeText = "The previous version of this file will be replaced."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        let proceed: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            if response == .alertFirstButtonReturn {
                self?.save(sender)
            }
        }
        if let window = windowControllers.first?.window {
            alert.beginSheetModal(for: window, completionHandler: proceed)
        } else {
            proceed(alert.runModal())
        }
    }

    /// First-responder action: Image ▸ Crop (PLAN.md §9).
    /// Disabled when there's no rect selection — see validateMenuItem(_:).
    @objc func cropImage(_ sender: Any?) {
        guard let model = self.model else { return }
        guard case .rect(let r) = model.selection, !r.isEmpty else { return }
        commit(CropAction(rect: r))
    }

    /// First-responder action: Image ▸ Resize… (PLAN.md §9).
    @objc func resizeImage(_ sender: Any?) {
        guard let model = self.model else { return }
        guard let parentWindow = windowControllers.first?.window else { return }
        let sheet = ResizeSheet(originalWidth: model.width, originalHeight: model.height)
        sheet.onCommit = { [weak self] (w: Int, h: Int, filter: ResampleFilter) in
            guard let self = self else { return }
            self.commit(ResizeAction(newWidth: w, newHeight: h, filter: filter))
        }
        // Retain so the sheet sticks around for the duration.
        objc_setAssociatedObject(self, &Self.kResizeSheetKey, sheet, .OBJC_ASSOCIATION_RETAIN)
        sheet.runModalSheet(on: parentWindow)
    }

    static var kResizeSheetKey: UInt8 = 0

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case Selector(("cropImage:")):
            if let model = self.model, case .rect(let r) = model.selection, !r.isEmpty {
                return true
            }
            return false
        case Selector(("deselect:")):
            if let model = self.model, case .rect = model.selection { return true }
            return false
        case Selector(("saveWithConfirm:")):
            // Match NSDocument's stock Save validation: enabled only when
            // there are unsaved changes (or no file yet, so a save panel is
            // still useful).
            return fileURL == nil || isDocumentEdited
        default:
            return super.validateMenuItem(menuItem)
        }
    }
}
