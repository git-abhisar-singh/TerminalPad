import Foundation

enum TerminalApp: String, CaseIterable, Identifiable {
    case terminal = "Terminal"
    case iterm = "iTerm2"
    case ghostty = "Ghostty"
    case warp = "Warp"
    var id: String { rawValue }
}

enum Launcher {
    static var preferred: TerminalApp {
        TerminalApp(rawValue: UserDefaults.standard.string(forKey: "terminalApp") ?? "") ?? .terminal
    }

    /// Opens a new window in the chosen terminal running `command` in the login shell.
    static func launch(_ command: String) {
        let esc = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        switch preferred {
        case .terminal:
            runOsascript("""
            tell application "Terminal"
                activate
                do script "\(esc)"
            end tell
            """)
        case .iterm:
            runOsascript("""
            tell application "iTerm"
                activate
                set w to (create window with default profile)
                tell current session of w to write text "\(esc)"
            end tell
            """)
        case .ghostty, .warp:
            // No AppleScript API; open the app then type via System Events (best effort).
            let app = preferred.rawValue
            run("/usr/bin/open", ["-na", app])
            runOsascript("""
            tell application "System Events"
                delay 0.6
                keystroke "\(esc)"
                key code 36
            end tell
            """)
        }
    }

    private static func runOsascript(_ script: String) {
        run("/usr/bin/osascript", ["-e", script])
    }

    private static func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        do { try p.run() } catch { NSLog("AgentPad: launch failed: \(error)") }
    }
}
