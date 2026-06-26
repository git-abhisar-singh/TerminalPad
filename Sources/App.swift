import SwiftUI
import AppKit

@main
struct AgentPadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .background(WindowConfigurator())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 880, height: 620)

        Settings { SettingsView() }

        MenuBarExtra {
            MenuBarContent()
        } label: {
            if let img = AppImages.menubar { Image(nsImage: img) }
            else { Image(systemName: "command") }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    // Stay alive in the menu bar after the window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// Makes the host NSWindow a transparent, glassy, Spotlight-style panel.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { [weak v] in
            guard let win = v?.window else { return }
            win.isOpaque = false
            win.backgroundColor = .clear
            win.titlebarAppearsTransparent = true
            win.titleVisibility = .hidden
            win.styleMask.insert(.fullSizeContentView)
            win.isMovableByWindowBackground = true
            win.standardWindowButton(.closeButton)?.superview?.alphaValue = 0.55
            win.appearance = NSAppearance(named: .vibrantDark)
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
