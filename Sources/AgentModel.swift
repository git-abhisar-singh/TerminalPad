import Foundation
import SwiftUI

struct Variant: Codable, Identifiable, Hashable {
    var id = UUID()
    var label: String
    var command: String
    var icon: String = "terminal"   // SF Symbol name
    var color: String = "#8E8E93"   // hex accent
    var cwd: String? = nil          // per-mode working directory (overrides agent.cwd)

    enum CodingKeys: String, CodingKey { case label, command, icon, color, cwd }

    var swiftColor: Color { Color(hex: color) }
}

struct Agent: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var icon: String         // short monogram text fallback, e.g. "CC"
    var color: String        // hex like "#D97757"
    var variants: [Variant]
    var logo: String? = nil   // logo slug -> Resources/logos/<slug>.png (else monogram)
    var aliases: [String] = [] // extra search keywords
    var cwd: String? = nil     // working directory to launch in
    var discovered: Bool = false

    enum CodingKeys: String, CodingKey { case name, icon, color, variants, logo, aliases, cwd }

    var swiftColor: Color { Color(hex: color) }
}

struct AgentConfig: Codable {
    var agents: [Agent]
}

/// Disk cache of the last discovery scan so tiles show instantly on launch
/// (stale-while-revalidate: render cache now, rescan in the background, update if changed).
enum DiscoveryCache {
    static var file: URL { ConfigStore.dir.appendingPathComponent("discovered.json") }

    static func load() -> [Agent] {
        guard let data = try? Data(contentsOf: file),
              let cfg = try? JSONDecoder().decode(AgentConfig.self, from: data) else { return [] }
        return cfg.agents
    }

    static func save(_ agents: [Agent]) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        guard let data = try? enc.encode(AgentConfig(agents: agents)) else { return }
        try? FileManager.default.createDirectory(at: ConfigStore.dir, withIntermediateDirectories: true)
        try? data.write(to: file)
    }
}

enum ConfigStore {
    static var dir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("agentpad", isDirectory: true)
    }
    static var file: URL { dir.appendingPathComponent("agents.json") }

    static func load() -> [Agent] {
        let fm = FileManager.default
        if !fm.fileExists(atPath: file.path) { seed() }
        do {
            let data = try Data(contentsOf: file)
            return try JSONDecoder().decode(AgentConfig.self, from: data).agents
        } catch {
            NSLog("AgentPad: config load failed: \(error). Using defaults.")
            return defaults
        }
    }

    static func seed() {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(AgentConfig(agents: defaults)) {
            try? data.write(to: file)
        }
    }

    static func save(_ agents: [Agent]) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(AgentConfig(agents: agents)) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: file)
        }
    }

    /// Force-rewrite defaults (used when upgrading the schema).
    static func reseed() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(AgentConfig(agents: defaults)) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: file)
        }
    }

    static let defaults: [Agent] = [
        Agent(name: "Claude Code", icon: "CC", color: "#D97757", variants: [
            Variant(label: "Normal",            command: "claude",                                  icon: "play.fill",            color: "#D97757"),
            Variant(label: "Skip Permissions",  command: "claude --dangerously-skip-permissions",   icon: "bolt.fill",            color: "#F4A261"),
            Variant(label: "Continue",          command: "claude -c",                               icon: "arrow.uturn.left",     color: "#C76A4E"),
            Variant(label: "Background",        command: "claude --bg",                             icon: "moon.fill",            color: "#9B5A42")
        ], logo: "claude", aliases: ["cc", "claude code"]),
        Agent(name: "Antigravity", icon: "AG", color: "#8E7CFF", variants: [
            Variant(label: "Normal",            command: "agy",                                     icon: "play.fill",            color: "#8E7CFF"),
            Variant(label: "Skip Permissions",  command: "agy --dangerously-skip-permissions",      icon: "bolt.fill",            color: "#B49CFF"),
            Variant(label: "Continue",          command: "agy --continue",                          icon: "arrow.uturn.left",     color: "#7466D6"),
            Variant(label: "Sandbox",           command: "agy --sandbox",                           icon: "shield.lefthalf.filled", color: "#5E52A8")
        ], logo: "antigravity", aliases: ["ag", "agy"]),
        Agent(name: "Gemini", icon: "GE", color: "#4285F4", variants: [
            Variant(label: "Normal",            command: "gemini",                                  icon: "play.fill",            color: "#4285F4"),
            Variant(label: "YOLO",              command: "gemini --yolo",                           icon: "flame.fill",           color: "#EA4335"),
            Variant(label: "Auto Edit",         command: "gemini --approval-mode auto_edit",        icon: "wand.and.stars",       color: "#34A853"),
            Variant(label: "Plan (read-only)",  command: "gemini --approval-mode plan",             icon: "doc.text.magnifyingglass", color: "#FBBC05")
        ], logo: "gemini", aliases: ["gg", "gem"]),
        Agent(name: "OpenCode", icon: "OC", color: "#10B981", variants: [
            Variant(label: "Normal (TUI)",      command: "opencode",                                icon: "play.fill",            color: "#10B981"),
            Variant(label: "Continue",          command: "opencode --continue",                     icon: "arrow.uturn.left",     color: "#0E9E72"),
            Variant(label: "Models",            command: "opencode models",                         icon: "square.stack.3d.up",   color: "#0B7A58")
        ], logo: "opencode", aliases: ["oc"]),
        Agent(name: "Ollama", icon: "OL", color: "#C9CDD3", variants: [
            Variant(label: "Gemma3 4B",         command: "ollama run gemma3:4b",                    icon: "cpu",                  color: "#C9CDD3"),
            Variant(label: "DeepSeek v3.1",     command: "ollama run deepseek-v3.1:671b-cloud",     icon: "cloud.fill",           color: "#8AA0FF"),
            Variant(label: "List Models",       command: "ollama list",                             icon: "list.bullet",          color: "#9AA0A6")
        ], logo: "ollama", aliases: ["ol", "llm"])
    ]
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        if s.count == 6 {
            self.init(.sRGB,
                      red: Double((v >> 16) & 0xFF) / 255,
                      green: Double((v >> 8) & 0xFF) / 255,
                      blue: Double(v & 0xFF) / 255,
                      opacity: 1)
        } else {
            self.init(.sRGB, red: 0.5, green: 0.5, blue: 0.5, opacity: 1)
        }
    }
}
