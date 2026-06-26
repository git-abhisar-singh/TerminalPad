import SwiftUI
import AppKit
import ServiceManagement

extension Notification.Name {
    static let agentpadReload = Notification.Name("agentpadReload")
    static let agentpadFocusSearch = Notification.Name("agentpadFocusSearch")
    static let agentpadOpenSettings = Notification.Name("agentpadOpenSettings")
}

enum AppImages {
    /// Menu-bar template image (adapts to light/dark).
    static let menubar: NSImage? = {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("menubar.png"),
              let img = NSImage(contentsOf: url) else { return nil }
        img.isTemplate = true
        img.size = NSSize(width: 18, height: 18)
        return img
    }()

    /// Full-colour app icon (multi-resolution .icns) — crisp at any size.
    static let appIcon: NSImage? = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: url) { return img }
        return NSApp.applicationIconImage
    }()
}

// MARK: - Settings window

struct SettingsView: View {
    @AppStorage("terminalApp") private var terminalApp = TerminalApp.terminal.rawValue
    @AppStorage("quitAfterLaunch") private var quitAfterLaunch = true
    @AppStorage("showDiscovered") private var showDiscovered = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("glassBlur") private var glassBlur = true
    @AppStorage("appearance") private var appearance = "system"
    @State private var resetConfirm = false

    var body: some View {
        Form {
            Section("Launching") {
                Picker("Terminal", selection: $terminalApp) {
                    ForEach(TerminalApp.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                Toggle("Quit AgentPad after launching", isOn: $quitAfterLaunch)
            }
            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                Toggle("Glass blur background", isOn: $glassBlur)
                Text("Glass on = live desktop blur (prettier, heavier GPU). Off = solid panel. Summon anywhere with ⌥⌘Space.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Library") {
                Toggle("Show discovered CLI tools", isOn: $showDiscovered)
                    .onChange(of: showDiscovered) { _, _ in post() }
                HStack {
                    Button("Edit agents.json…") { openConfig() }
                    Button("Rescan tools") { post() }
                    Button("Reset to defaults") { resetConfirm = true }
                        .confirmationDialog("Reset agents.json to defaults?", isPresented: $resetConfirm) {
                            Button("Reset", role: .destructive) { ConfigStore.reseed(); post() }
                        }
                }
            }
            Section("System") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLoginItem(on) }
            }
            Section {
                Text("Edit \(ConfigStore.file.path) to add agents and modes. Logos resolve from Resources/logos or Simple Icons.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 420)
    }

    private func post() { NotificationCenter.default.post(name: .agentpadReload, object: nil) }
    private func openConfig() {
        if !FileManager.default.fileExists(atPath: ConfigStore.file.path) { ConfigStore.seed() }
        NSWorkspace.shared.open(ConfigStore.file)
    }
    private func setLoginItem(_ on: Bool) {
        do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
        catch { NSLog("AgentPad: login item error: \(error)") }
    }
}

/// In-app Settings presented as a sheet (gear button in the header).
struct SettingsSheet: View {
    let onDone: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Done", action: onDone).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            Divider()
            SettingsView()
        }
        .frame(width: 460)
        .preferredColorScheme(.dark)
    }
}

