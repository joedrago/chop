import AppKit
import Foundation
import os

extension AppDelegate {
    /// Symlink the embedded `chop` CLI shim into `/usr/local/bin/chop`.
    /// Uses an authorization prompt via `osascript`
    /// since `/usr/local/bin/` typically isn't writable by the user.
    @objc func installCommandLineTool(_ sender: Any?) {
        guard let embedded = embeddedCLIPath() else {
            presentMissingShimAlert()
            return
        }

        let target = URL(fileURLWithPath: "/usr/local/bin/chop")

        // If the symlink already points at us, just confirm.
        if FileManager.default.fileExists(atPath: target.path),
            let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: target.path),
            dest == embedded.path
        {
            presentAlreadyInstalledAlert(at: target)
            return
        }

        let confirm = NSAlert()
        confirm.messageText = "Install Command Line Tool"
        confirm.informativeText =
            "Install the `chop` command at \(target.path)?\n\n"
            + "This will create a symbolic link to the chop helper "
            + "inside Chop.app. You may be prompted to authenticate."
        confirm.addButton(withTitle: "Install")
        confirm.addButton(withTitle: "Cancel")
        if confirm.runModal() != .alertFirstButtonReturn {
            return
        }

        do {
            try installSymlink(from: embedded, to: target)
            let done = NSAlert()
            done.messageText = "Installed"
            done.informativeText = "You can now run `chop` from your shell."
            done.runModal()
        } catch {
            let fail = NSAlert()
            fail.alertStyle = .warning
            fail.messageText = "Install Failed"
            fail.informativeText = error.localizedDescription
            fail.runModal()
        }
    }

    private func embeddedCLIPath() -> URL? {
        // Inside Chop.app the shim lives at Contents/SharedSupport/chop.
        // (We can't use Contents/MacOS because APFS is case-insensitive
        // and the app's `Chop` binary would collide.)
        let candidate = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("SharedSupport", isDirectory: true)
            .appendingPathComponent("chop")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        return nil
    }

    private func installSymlink(from src: URL, to dst: URL) throws {
        // Try the easy path: user has write access to /usr/local/bin already.
        let dir = dst.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        if FileManager.default.isWritableFile(atPath: dir.path) {
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.createSymbolicLink(at: dst, withDestinationURL: src)
            return
        }
        // Otherwise, ask the system to do it with admin privileges via
        // AppleScript. Safer than rolling our own SMJobBless plumbing for v1.
        let script =
            """
            do shell script "mkdir -p \(dir.path); rm -f \(dst.path); \
            ln -s \(escape(src.path)) \(escape(dst.path))" \
            with administrator privileges
            """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        let stderr = Pipe()
        task.standardError = stderr
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message =
                String(data: data, encoding: .utf8) ?? "Authorization cancelled."
            throw NSError(
                domain: "ChopCLIInstall",
                code: Int(task.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }

    private func escape(_ path: String) -> String {
        // Quote for inclusion inside an AppleScript double-quoted shell command.
        let escaped = path.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\\\"" + escaped + "\\\""
    }

    private func presentMissingShimAlert() {
        let alert = NSAlert()
        alert.messageText = "chop Helper Not Found"
        alert.informativeText =
            "The chop command-line helper is not present inside this build of "
            + "Chop.app. Reinstall Chop or run `make build` from a fresh "
            + "checkout."
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func presentAlreadyInstalledAlert(at url: URL) {
        let alert = NSAlert()
        alert.messageText = "Already Installed"
        alert.informativeText = "`chop` is already linked at \(url.path)."
        alert.runModal()
    }
}
