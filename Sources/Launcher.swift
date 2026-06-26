import Foundation

enum Launcher {
    /// Opens a NEW Terminal.app window running `command` in the login shell.
    static func launch(_ command: String) {
        // Escape for embedding inside an AppleScript double-quoted string.
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        do {
            try proc.run()
        } catch {
            NSLog("AgentPad: launch failed: \(error)")
        }
    }
}
