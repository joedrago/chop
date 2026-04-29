import AppKit

/// Minimal above-canvas toolbar. Open, Save, and view-mode shortcuts.
/// Tool selection lives in the side `ToolboxView`.
@MainActor
final class ChopToolbar: NSObject, NSToolbarDelegate {
    private static let identifier = NSToolbar.Identifier("ChopMainToolbar")
    weak var windowController: ChopWindowController?

    enum Item: String, CaseIterable {
        case open
        case save
        case zoomIn
        case zoomOut
        case actualSize
        case fitToWindow

        var title: String {
            switch self {
            case .open: return "Open"
            case .save: return "Save"
            case .zoomIn: return "Zoom In"
            case .zoomOut: return "Zoom Out"
            case .actualSize: return "100%"
            case .fitToWindow: return "Fit"
            }
        }

        var symbolName: String {
            switch self {
            case .open: return "folder"
            case .save: return "square.and.arrow.down"
            case .zoomIn: return "plus.magnifyingglass"
            case .zoomOut: return "minus.magnifyingglass"
            case .actualSize: return "1.square"
            case .fitToWindow: return "rectangle.expand.vertical"
            }
        }

        var itemIdentifier: NSToolbarItem.Identifier {
            NSToolbarItem.Identifier("Chop.\(rawValue)")
        }
    }

    func install(on window: NSWindow) {
        let toolbar = NSToolbar(identifier: Self.identifier)
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        toolbar.displayMode = .iconOnly
        toolbar.delegate = self
        window.toolbar = toolbar
        window.toolbarStyle = .unifiedCompact
    }

    // MARK: - NSToolbarDelegate

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let item = Item.allCases.first(where: { $0.itemIdentifier == itemIdentifier })
        else {
            return nil
        }
        let toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)
        toolbarItem.label = item.title
        toolbarItem.paletteLabel = item.title
        toolbarItem.toolTip = item.title
        // SF Symbols have varying intrinsic bounding-box sizes (e.g. rectangle.dashed
        // renders smaller than hand.raised at default size). Pin every toolbar
        // image to a consistent SymbolConfiguration so they line up visually.
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            .applying(NSImage.SymbolConfiguration(scale: .large))
        let image = NSImage(
            systemSymbolName: item.symbolName,
            accessibilityDescription: item.title
        )?.withSymbolConfiguration(symbolConfig)
        toolbarItem.image = image
        toolbarItem.isBordered = true
        toolbarItem.target = self
        toolbarItem.action = #selector(handleToolbarItem(_:))
        toolbarItem.tag = item.tag
        return toolbarItem
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            Item.open.itemIdentifier,
            Item.save.itemIdentifier,
            .flexibleSpace,
            Item.zoomOut.itemIdentifier,
            Item.actualSize.itemIdentifier,
            Item.zoomIn.itemIdentifier,
            Item.fitToWindow.itemIdentifier,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Item.allCases.map { $0.itemIdentifier } + [.space, .flexibleSpace, .flexibleSpace]
    }

    @objc private func handleToolbarItem(_ sender: NSToolbarItem) {
        guard let item = Item.allCases.first(where: { $0.tag == sender.tag }) else { return }
        switch item {
        case .open:
            NSDocumentController.shared.openDocument(sender)
        case .save:
            (windowController?.document as? NSDocument)?.save(sender)
        case .zoomIn:
            windowController?.zoomIn(sender)
        case .zoomOut:
            windowController?.zoomOut(sender)
        case .actualSize:
            windowController?.actualSize(sender)
        case .fitToWindow:
            windowController?.fitToWindow(sender)
        }
    }
}

extension ChopToolbar.Item {
    var tag: Int {
        switch self {
        case .open: return 1
        case .save: return 2
        case .zoomIn: return 6
        case .zoomOut: return 7
        case .actualSize: return 8
        case .fitToWindow: return 9
        }
    }
}
