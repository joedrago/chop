import AppKit

/// Builds the application's main menu programmatically (PLAN.md §9).
/// No xib / storyboard files; everything lives in Swift.
@MainActor
final class MainMenuController {
    func buildMainMenu() -> NSMenu {
        let main = NSMenu()
        main.addItem(makeAppMenu())
        main.addItem(makeFileMenu())
        main.addItem(makeEditMenu())
        main.addItem(makeImageMenu())
        main.addItem(makeViewMenu())
        main.addItem(makeWindowMenu())
        main.addItem(makeHelpMenu())
        return main
    }

    private func makeAppMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Chop")

        menu.addItem(
            withTitle: "About Chop",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )

        menu.addItem(NSMenuItem.separator())

        menu.addItem(
            withTitle: "Settings…",
            action: nil,
            keyEquivalent: ","
        )

        menu.addItem(NSMenuItem.separator())

        let installItem = menu.addItem(
            withTitle: "Install Command Line Tool…",
            action: #selector(AppDelegate.installCommandLineTool(_:)),
            keyEquivalent: ""
        )
        installItem.target = NSApp.delegate

        menu.addItem(NSMenuItem.separator())

        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        services.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        menu.addItem(services)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(
            withTitle: "Hide Chop",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )

        let hideOthers = menu.addItem(
            withTitle: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]

        menu.addItem(
            withTitle: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )

        menu.addItem(NSMenuItem.separator())

        menu.addItem(
            withTitle: "Quit Chop",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        item.submenu = menu
        return item
    }

    private func makeFileMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "File")

        menu.addItem(
            withTitle: "Open…",
            action: #selector(NSDocumentController.openDocument(_:)),
            keyEquivalent: "o"
        )

        // AppKit auto-attaches the "Open Recent" submenu when the app has
        // NSDocument types registered with NSDocumentClass. Don't add a
        // second one here.

        menu.addItem(NSMenuItem.separator())

        menu.addItem(
            withTitle: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )

        menu.addItem(
            withTitle: "Save",
            action: #selector(NSDocument.save(_:)),
            keyEquivalent: "s"
        )

        let saveAs = menu.addItem(
            withTitle: "Save As…",
            action: #selector(NSDocument.saveAs(_:)),
            keyEquivalent: "S"
        )
        saveAs.keyEquivalentModifierMask = [.command, .shift]

        menu.addItem(
            withTitle: "Revert to Saved",
            action: #selector(NSDocument.revertToSaved(_:)),
            keyEquivalent: ""
        )

        item.submenu = menu
        return item
    }

    private func makeEditMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Edit")

        menu.addItem(
            withTitle: "Undo",
            action: Selector(("undo:")),
            keyEquivalent: "z"
        )

        let redo = menu.addItem(
            withTitle: "Redo",
            action: Selector(("redo:")),
            keyEquivalent: "Z"
        )
        redo.keyEquivalentModifierMask = [.command, .shift]

        menu.addItem(NSMenuItem.separator())

        menu.addItem(
            withTitle: "Cut",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )

        menu.addItem(
            withTitle: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )

        menu.addItem(
            withTitle: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )

        menu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )

        menu.addItem(NSMenuItem.separator())

        menu.addItem(
            withTitle: "Deselect",
            action: Selector(("deselect:")),
            keyEquivalent: "d"
        )

        item.submenu = menu
        return item
    }

    private func makeImageMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Image")

        menu.addItem(
            withTitle: "Resize…",
            action: Selector(("resizeImage:")),
            keyEquivalent: "r"
        )

        menu.addItem(
            withTitle: "Crop",
            action: Selector(("cropImage:")),
            keyEquivalent: ""
        )

        item.submenu = menu
        return item
    }

    private func makeViewMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "View")

        menu.addItem(
            withTitle: "Zoom In",
            action: Selector(("zoomIn:")),
            keyEquivalent: "="
        )

        menu.addItem(
            withTitle: "Zoom Out",
            action: Selector(("zoomOut:")),
            keyEquivalent: "-"
        )

        menu.addItem(
            withTitle: "Actual Size",
            action: Selector(("actualSize:")),
            keyEquivalent: "1"
        )

        menu.addItem(
            withTitle: "Fit to Window",
            action: Selector(("fitToWindow:")),
            keyEquivalent: "0"
        )

        menu.addItem(NSMenuItem.separator())

        let showTabBar = menu.addItem(
            withTitle: "Show Tab Bar",
            action: #selector(NSWindow.toggleTabBar(_:)),
            keyEquivalent: "T"
        )
        showTabBar.keyEquivalentModifierMask = [.command, .shift]

        item.submenu = menu
        return item
    }

    private func makeWindowMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Window")

        menu.addItem(
            withTitle: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )

        menu.addItem(
            withTitle: "Zoom",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )

        menu.addItem(NSMenuItem.separator())

        menu.addItem(
            withTitle: "Bring All to Front",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )

        item.submenu = menu
        NSApp.windowsMenu = menu
        return item
    }

    private func makeHelpMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Help")

        menu.addItem(
            withTitle: "Chop Help",
            action: #selector(NSApplication.showHelp(_:)),
            keyEquivalent: "?"
        )

        item.submenu = menu
        NSApp.helpMenu = menu
        return item
    }
}
