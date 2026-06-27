import SwiftUI
import AppKit
import ServiceManagement

extension Notification.Name {
    static let terminalpadReload = Notification.Name("terminalpadReload")
    static let terminalpadFocusSearch = Notification.Name("terminalpadFocusSearch")
    static let terminalpadOpenSettings = Notification.Name("terminalpadOpenSettings")
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
    @AppStorage("rescanOnLaunch") private var rescanOnLaunch = true
    @AppStorage("hapticLevel") private var hapticLevel = "strong"
    @State private var resetConfirm = false
    @State private var keepOnSpace = Launcher.keepAppsOnCurrentSpace
    @State private var newName = ""
    @State private var newCommand = ""
    @State private var newAlias = ""
    @State private var newColor = "#5B8DEF"
    @State private var updateStatus = ""
    @State private var agents: [Agent] = ConfigStore.load()

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        Form {
            Section("Launching") {
                Picker("Terminal", selection: $terminalApp) {
                    ForEach(TerminalApp.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                Toggle("Quit TerminalPad after launching", isOn: $quitAfterLaunch)
                Picker("Hover haptics", selection: $hapticLevel) {
                    Text("Off").tag("off")
                    Text("Light").tag("light")
                    Text("Medium").tag("medium")
                    Text("Strong").tag("strong")
                }
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
                Toggle("Rescan tools on launch", isOn: $rescanOnLaunch)
                HStack {
                    Button("Edit agents.json…") { openConfig() }
                    Button("Rescan tools") { post() }
                    Button("Refresh logos") { refreshLogos() }
                    Button("Reset to defaults") { resetConfirm = true }
                        .confirmationDialog("Reset agents.json to defaults?", isPresented: $resetConfirm) {
                            Button("Reset", role: .destructive) { ConfigStore.reseed(); agents = ConfigStore.load(); post() }
                        }
                }
            }
            Section("Agents") {
                ForEach($agents) { $agent in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            TextField("Name", text: $agent.name)
                            TextField("#color", text: $agent.color).frame(width: 76)
                            Button { moveUp(agent.id) } label: { Image(systemName: "chevron.up") }
                                .buttonStyle(.borderless)
                            Button { moveDown(agent.id) } label: { Image(systemName: "chevron.down") }
                                .buttonStyle(.borderless)
                            Button(role: .destructive) { agents.removeAll { $0.id == agent.id } } label: {
                                Image(systemName: "trash")
                            }.buttonStyle(.borderless)
                        }
                        if !agent.variants.isEmpty {
                            TextField("Command", text: $agent.variants[0].command)
                                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Save Changes") { saveAgents() }
            }
            Section("Add Agent") {
                TextField("Name", text: $newName)
                TextField("Command (e.g. aider --yes)", text: $newCommand)
                TextField("Aliases, comma-separated (optional)", text: $newAlias)
                TextField("Color hex (optional)", text: $newColor)
                Button("Add Agent") { addAgent() }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty
                              || newCommand.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Section("System") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLoginItem(on) }
                Toggle("Open apps on the current desktop", isOn: $keepOnSpace)
                    .onChange(of: keepOnSpace) { _, on in Launcher.setKeepAppsOnCurrentSpace(on) }
                Text("Stops macOS jumping to another Space when an app already has a window there. This changes a system-wide Mission Control setting.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("About") {
                HStack {
                    Text("Version \(version)").foregroundStyle(.secondary)
                    Spacer()
                    Button("Check for Updates") { checkUpdate() }
                    if !updateStatus.isEmpty {
                        Text(updateStatus).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func addAgent() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        let cmd = newCommand.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !cmd.isEmpty else { return }
        let aliases = newAlias.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let color = newColor.hasPrefix("#") ? newColor : "#5B8DEF"
        let mono = String(name.prefix(2)).uppercased()
        let logoSlug = cmd.split(separator: " ").first.map(String.init)
        agents.append(Agent(name: name, icon: mono, color: color,
                            variants: [Variant(label: "Run", command: cmd, icon: "terminal", color: color)],
                            logo: logoSlug, aliases: aliases))
        saveAgents()
        newName = ""; newCommand = ""; newAlias = ""; newColor = "#5B8DEF"
    }

    private func saveAgents() { ConfigStore.save(agents); post() }
    private func moveUp(_ id: UUID) {
        if let i = agents.firstIndex(where: { $0.id == id }), i > 0 { agents.swapAt(i, i - 1) }
    }
    private func moveDown(_ id: UUID) {
        if let i = agents.firstIndex(where: { $0.id == id }), i < agents.count - 1 { agents.swapAt(i, i + 1) }
    }

    private func refreshLogos() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/terminalpad/logos")
        try? FileManager.default.removeItem(at: dir)
        post()
    }

    private func checkUpdate() {
        updateStatus = "Checking…"
        Task {
            guard let url = URL(string: "https://api.github.com/repos/git-abhisar-singh/TerminalPad/releases/latest"),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                await MainActor.run { updateStatus = "No releases yet" }
                return
            }
            await MainActor.run {
                updateStatus = tag.contains(version) ? "Up to date" : "Update: \(tag)"
            }
        }
    }

    private func post() { NotificationCenter.default.post(name: .terminalpadReload, object: nil) }
    private func openConfig() {
        if !FileManager.default.fileExists(atPath: ConfigStore.file.path) { ConfigStore.seed() }
        NSWorkspace.shared.open(ConfigStore.file)
    }
    private func setLoginItem(_ on: Bool) {
        do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
        catch { NSLog("TerminalPad: login item error: \(error)") }
    }
}


