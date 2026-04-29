import AppKit
import Foundation

// Tiny shim — hand URLs (or zero URLs) to NSWorkspace and exit. The OS
// routes file URLs into the running Chop.app via AppleEvents

let args = Array(CommandLine.arguments.dropFirst())
let prog = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "chop"

if args.contains("--version") {
    print("chop 0.1.0")
    exit(0)
}
if args.contains("--help") || args.contains("-h") {
    print(
        """
        usage: \(prog) [files...]

        Open files in Chop.app, launching it if necessary. Returns immediately.
        """
    )
    exit(0)
}

// Filter to file URLs that exist (or could be opened later); pass them all.
let urls = args.map { URL(fileURLWithPath: $0).standardizedFileURL }

let appURL: URL = {
    // Prefer the bundled embedded app if we're running from inside Chop.app
    // (or via a symlink that resolves there). The shim lives at
    // Contents/SharedSupport/chop so the .app is two parents up.
    let exec = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let two = exec.deletingLastPathComponent().deletingLastPathComponent()
    if two.pathExtension == "app" {
        return two
    }
    let three = two.deletingLastPathComponent()
    if three.pathExtension == "app" {
        return three
    }
    return URL(fileURLWithPath: "/Applications/Chop.app")
}()

let cfg = NSWorkspace.OpenConfiguration()
cfg.activates = true

let group = DispatchGroup()
group.enter()

if urls.isEmpty {
    NSWorkspace.shared.openApplication(at: appURL, configuration: cfg) { _, error in
        if let error = error {
            FileHandle.standardError.write(
                "chop: \(error.localizedDescription)\n".data(using: .utf8) ?? Data()
            )
        }
        group.leave()
    }
} else {
    NSWorkspace.shared.open(
        urls,
        withApplicationAt: appURL,
        configuration: cfg
    ) { _, error in
        if let error = error {
            FileHandle.standardError.write(
                "chop: \(error.localizedDescription)\n".data(using: .utf8) ?? Data()
            )
        }
        group.leave()
    }
}

_ = group.wait(timeout: .now() + .seconds(5))
exit(0)
