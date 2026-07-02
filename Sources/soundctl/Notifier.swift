import Foundation

/// Posts macOS notifications by shelling out to `osascript`.
///
/// A command-line binary has no application bundle, so the `UserNotifications`
/// framework can't reliably obtain authorization or a bundle identifier. Driving
/// AppleScript's `display notification` is the dependency-free path that works
/// from an unbundled tool. All calls are best-effort and never throw.
enum Notifier {
    /// Post a notification. Silently does nothing if `osascript` is unavailable
    /// or fails — a missing toast should never break an audio switch.
    static func notify(title: String, body: String) {
        let script = "display notification \(quote(body)) with title \(quote(title))"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // Best-effort: ignore failures.
        }
    }

    /// Wrap a string as an AppleScript string literal, escaping backslashes and
    /// quotes. Values are passed to `osascript` as `Process` arguments (not via a
    /// shell), so only AppleScript-level quoting is required.
    private static func quote(_ string: String) -> String {
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
