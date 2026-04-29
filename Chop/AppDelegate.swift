import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuController: MainMenuController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        // Note: activation must happen AFTER the runloop is up — calling it
        // here is a no-op. See applicationDidFinishLaunching.
        app.run()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        let controller = MainMenuController()
        NSApp.mainMenu = controller.buildMainMenu()
        self.menuController = controller
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        chopLog("Chop launched.")
        // Explicitly load the app icon — LaunchServices doesn't always pick
        // up CFBundleIconFile for Debug builds in non-installed locations
        // (and `make log` runs the binary outside LaunchServices entirely).
        if let iconPath = Bundle.main.path(forResource: "Chop", ofType: "icns"),
            let icon = NSImage(contentsOfFile: iconPath)
        {
            NSApp.applicationIconImage = icon
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// No untitled window on launch.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    /// Don't quit when the last window closes; the menu bar stays alive.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// AppleEvent (`open foo.png`, drag-onto-Dock, Finder open) routes here.
    func application(_ application: NSApplication, open urls: [URL]) {
        let controller = NSDocumentController.shared
        for url in urls {
            controller.openDocument(withContentsOf: url, display: true) {
                doc,
                alreadyOpen,
                error in
                if let error = error {
                    chopLog("openDocument failed for \(url.path): \(error)")
                    Self.presentOpenError(url: url, error: error)
                } else {
                    chopLog(
                        "openDocument: url=\(url.path) alreadyOpen=\(alreadyOpen) "
                            + "doc=\(doc != nil)"
                    )
                }
            }
        }
    }

    @MainActor
    static func presentOpenError(url: URL, error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Could not open \(url.lastPathComponent)"
        alert.runModal()
    }
}
