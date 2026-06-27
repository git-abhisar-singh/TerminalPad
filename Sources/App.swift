import SwiftUI
import AppKit

@main
struct TerminalPadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .background(WindowConfigurator())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 880, height: 620)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { post(.terminalpadOpenSettings) }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .toolbar) {
                Button("Search") { post(.terminalpadFocusSearch) }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Rescan Tools") { post(.terminalpadReload) }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

func post(_ name: Notification.Name) { NotificationCenter.default.post(name: name, object: nil) }

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        setupMenuBar()

        HotKeyManager.shared.onTrigger = { [weak self] in
            if NSApp.isActive { NSApp.hide(nil) } else { self?.showMain() }
        }
        HotKeyManager.shared.register()
    }

    // Stay alive in the menu bar after the window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // Dock-click / reopen brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showMain(); return true
    }

    private func mainWindow() -> NSWindow? {
        NSApp.windows.first { $0.title == "TerminalPad" }
    }

    func showMain() {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow()?.makeKeyAndOrderFront(nil)
        post(.terminalpadFocusSearch)
    }

    // MARK: AppKit menu bar (no phantom window, unlike SwiftUI MenuBarExtra)

    private func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let img = AppImages.menubar {
            img.isTemplate = true            // adapt to light / dark / translucent menu bar
            item.button?.image = img
            item.button?.image?.isTemplate = true
        } else {
            item.button?.title = "TP"
        }

        let menu = NSMenu()
        menu.autoenablesItems = false        // we set valid targets ourselves; don't auto-disable

        let open = NSMenuItem(title: "Open TerminalPad", action: #selector(openMain), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())

        for agent in ConfigStore.load() {
            if agent.variants.first != nil {
                let mi = NSMenuItem(title: "\(agent.name) — \(agent.variants[0].label)",
                                    action: #selector(launchAgent(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = agent          // carry the whole agent (for the app fallback)
                menu.addItem(mi)
            }
        }

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        // Quit must target NSApp (AppDelegate doesn't respond to terminate:).
        let quit = NSMenuItem(title: "Quit TerminalPad", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    @objc private func openMain() { showMain() }
    @objc private func launchAgent(_ sender: NSMenuItem) {
        guard let agent = sender.representedObject as? Agent, let v = agent.variants.first else { return }
        NSApp.activate(ignoringOtherApps: true)
        // Same CLI-vs-app logic as the grid: open the app if the CLI isn't installed.
        let base = Discovery.firstWord(v.command)
        if !Discovery.commandExists(base), let app = agent.app, Discovery.isAppInstalled(app) {
            Launcher.openApp(app)
        } else {
            Launcher.launch(v.command, cwd: agent.cwd)
        }
    }
    @objc private func openSettings() {
        showMain()
        post(.terminalpadOpenSettings)
    }
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
            win.setFrameAutosaveName("TerminalPadMainWindow")   // remember size/position
            // Unified toolbar makes the titlebar taller so the traffic lights
            // sit lower with breathing room (and the system keeps them centred).
            let tb = NSToolbar(identifier: "ap.toolbar")
            tb.showsBaselineSeparator = false
            win.toolbar = tb
            win.toolbarStyle = .unified

            // A transparent Spotlight-style panel must never go full screen (the
            // titlebar/toolbar collapse and the clear panel fills the display).
            // Disable full screen + zoom so it stays a floating, resizable launcher.
            win.collectionBehavior.remove(.fullScreenPrimary)
            win.collectionBehavior.insert(.fullScreenNone)
            win.standardWindowButton(.zoomButton)?.isEnabled = false
            if win.styleMask.contains(.fullScreen) { win.toggleFullScreen(nil) }

            win.invalidateShadow()
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
