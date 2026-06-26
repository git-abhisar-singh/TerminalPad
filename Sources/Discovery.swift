import Foundation

/// Scans the Mac for installed command-line tools and turns each into a launchable Agent.
enum Discovery {
    static let binDirs: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/opt/homebrew/bin", "/opt/homebrew/sbin",
            "/usr/local/bin", "/usr/local/sbin",
            "\(home)/.local/bin", "/usr/bin"
        ]
    }()

    /// command-name overrides for formulae whose primary binary differs from the formula name.
    static let aliases: [String: String] = [
        "postgresql": "psql", "redis": "redis-cli", "python": "python3",
        "openjdk": "java", "sqlite": "sqlite3", "imagemagick": "magick",
        "ripgrep": "rg", "the_silver_searcher": "ag"
    ]

    /// Tools that aren't meaningfully runnable on their own (libs / build deps) — skip.
    static let skip: Set<String> = [
        "portaudio", "openssl", "ca-certificates", "readline", "libyaml",
        "pkg-config", "gmp", "mpfr", "libtool", "icu4c", "zlib", "xz",
        "lz4", "zstd", "pcre2", "gettext", "sqlite"
    ]

    static func run(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func resolve(_ rawName: String) -> (cmd: String, path: String)? {
        // strip tap prefix (anomalyco/tap/opencode -> opencode) and @version
        var name = rawName.split(separator: "/").last.map(String.init) ?? rawName
        if let at = name.firstIndex(of: "@") { name = String(name[..<at]) }
        if skip.contains(name) { return nil }
        let candidate = aliases[name] ?? name
        for dir in binDirs {
            let full = "\(dir)/\(candidate)"
            if FileManager.default.isExecutableFile(atPath: full) {
                return (candidate, full)
            }
        }
        return nil
    }

    /// Returns discovered tools as Agents, excluding any command already covered by curated agents.
    static func tools(excluding curated: Set<String>) -> [Agent] {
        var names: [String] = []

        // 1. Homebrew installed-on-request formulae
        let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
        if let brew {
            names += run(brew, ["leaves"]).split(whereSeparator: \.isNewline).map(String.init)
        }

        // 2. user-local bins
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if let local = try? FileManager.default.contentsOfDirectory(atPath: "\(home)/.local/bin") {
            names += local
        }

        var seen = Set<String>()
        var out: [Agent] = []
        for raw in names {
            guard let (cmd, _) = resolve(raw.trimmingCharacters(in: .whitespaces)) else { continue }
            if curated.contains(cmd) || seen.contains(cmd) { continue }
            seen.insert(cmd)
            out.append(makeAgent(cmd))
        }
        return out.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// command -> simpleicons / bundled-logo slug (when they differ from the command name).
    static let logoSlug: [String: String] = [
        "python3": "python", "redis-cli": "redis", "psql": "postgresql",
        "java": "openjdk", "magick": "imagemagick", "rg": "ripgrep", "ag": "thesilversearcher"
    ]

    /// command -> nicer display name.
    static let nameOverride: [String: String] = [
        "gh": "GitHub CLI", "psql": "PostgreSQL", "redis-cli": "Redis",
        "python3": "Python", "ffmpeg": "FFmpeg", "rg": "ripgrep", "yt-dlp": "yt-dlp"
    ]

    static func makeAgent(_ cmd: String) -> Agent {
        let title = nameOverride[cmd] ?? cmd
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
        let mono = String(cmd.prefix(2)).uppercased()
        return Agent(
            name: title,
            icon: mono,
            color: stableColor(cmd),
            variants: [Variant(label: "Run", command: cmd, icon: "terminal", color: stableColor(cmd))],
            logo: logoSlug[cmd] ?? cmd,
            discovered: true
        )
    }

    /// Deterministic pleasant color per tool name.
    static func stableColor(_ s: String) -> String {
        var h: UInt64 = 5381
        for b in s.utf8 { h = ((h << 5) &+ h) &+ UInt64(b) }
        let hue = Double(h % 360)
        return hslHex(hue: hue, sat: 0.42, light: 0.55)
    }

    static func hslHex(hue: Double, sat: Double, light: Double) -> String {
        let c = (1 - abs(2 * light - 1)) * sat
        let x = c * (1 - abs((hue / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = light - c / 2
        let (r, g, b): (Double, Double, Double)
        switch hue {
        case ..<60:   (r, g, b) = (c, x, 0)
        case ..<120:  (r, g, b) = (x, c, 0)
        case ..<180:  (r, g, b) = (0, c, x)
        case ..<240:  (r, g, b) = (0, x, c)
        case ..<300:  (r, g, b) = (x, 0, c)
        default:      (r, g, b) = (c, 0, x)
        }
        let R = Int((r + m) * 255), G = Int((g + m) * 255), B = Int((b + m) * 255)
        return String(format: "#%02X%02X%02X", R, G, B)
    }
}
