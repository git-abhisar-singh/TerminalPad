import Foundation

/// Scans the Mac for installed command-line tools and turns each into a launchable Agent.
enum Discovery {
    static let binDirs: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/opt/homebrew/bin", "/opt/homebrew/sbin",
            "/usr/local/bin", "/usr/local/sbin",
            "\(home)/.local/bin", "\(home)/.cargo/bin", "\(home)/go/bin",
            "\(home)/.bun/bin", "/usr/bin"
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
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // The 3 subprocess scans (brew ~1.2s, npm ~0.4s, pipx ~0.1s) are independent —
        // run them concurrently so the scan costs max(...) not sum(...).
        let group = DispatchGroup()
        let lock = NSLock()
        var names: [String] = []
        func add(_ items: [String]) { lock.lock(); names += items; lock.unlock() }

        // 1. Homebrew installed-on-request formulae
        if let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            group.enter()
            DispatchQueue.global().async {
                add(run(brew, ["leaves"]).split(whereSeparator: \.isNewline).map(String.init))
                group.leave()
            }
        }

        // 2. npm global packages
        if let npm = ["/opt/homebrew/bin/npm", "/usr/local/bin/npm"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            group.enter()
            DispatchQueue.global().async {
                add(run(npm, ["ls", "-g", "--depth=0", "--parseable"])
                    .split(whereSeparator: \.isNewline)
                    .compactMap { $0.split(separator: "/").last.map(String.init) }
                    .filter { $0 != "lib" && !$0.hasPrefix("@") })
                group.leave()
            }
        }

        // 3. pipx apps
        if let pipx = ["/opt/homebrew/bin/pipx", "\(home)/.local/bin/pipx"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            group.enter()
            DispatchQueue.global().async {
                add(run(pipx, ["list", "--short"])
                    .split(whereSeparator: \.isNewline)
                    .compactMap { $0.split(separator: " ").first.map(String.init) })
                group.leave()
            }
        }

        // 4. user-local / language bins (cargo, go, bun, etc.) — cheap dir reads, do inline
        for dir in ["\(home)/.local/bin", "\(home)/.cargo/bin", "\(home)/go/bin", "\(home)/.bun/bin"] {
            if let items = try? FileManager.default.contentsOfDirectory(atPath: dir) { add(items) }
        }

        group.wait()

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

    /// Brand colors for popular tools (else a stable per-name color).
    static let brandColors: [String: String] = [
        "docker": "#2496ED", "node": "#5FA04E", "python3": "#3776AB", "redis-cli": "#FF4438",
        "psql": "#4169E1", "git": "#F05032", "gh": "#6E5494", "ffmpeg": "#388E3C",
        "go": "#00ADD8", "cargo": "#DEA584", "ruby": "#CC342D", "php": "#777BB4",
        "deno": "#3C9F4A", "bun": "#E5B95C", "mysql": "#4479A1", "mongosh": "#47A248",
        "kubectl": "#326CE5", "terraform": "#7B42BC", "ansible": "#1A1918", "ngrok": "#5C66E8",
        "vercel": "#3A6CF6", "pnpm": "#F69220", "yarn": "#2C8EBB", "vim": "#019733",
        "nvim": "#57A143", "tmux": "#1BB91F", "htop": "#0F9D58", "pandoc": "#3A66A7",
        "java": "#E76F00", "pipx": "#3776AB", "cloudflared": "#F38020"
    ]

    static func makeAgent(_ cmd: String) -> Agent {
        let title = nameOverride[cmd] ?? cmd
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
        let mono = String(cmd.prefix(2)).uppercased()
        let color = brandColors[cmd] ?? stableColor(cmd)
        return Agent(
            name: title,
            icon: mono,
            color: color,
            variants: [Variant(label: "Run", command: cmd, icon: "terminal", color: color)],
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
