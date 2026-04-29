import Darwin
import Foundation

/// Lightweight printf-style logger for development.
///
/// Writes to stderr only when stderr is attached to a TTY — so when the
/// .app is launched via Finder or `open`, this is silent (no system-log
/// pollution). When launched directly via `make log`, the binary runs in
/// the foreground with stdio attached and these messages stream into the
/// terminal.
@inlinable
func chopLog(_ message: @autoclosure () -> String) {
    guard isatty(fileno(stderr)) != 0 else { return }
    var line = message()
    line.append("\n")
    line.withCString { cstr in
        _ = fputs(cstr, stderr)
    }
    fflush(stderr)
}
