import Foundation

/// Scans the Mac for installed command-line tools and turns each into a launchable Agent.
enum Discovery {
    /// command-name overrides for formulae whose primary binary differs from the formula name.
    static let aliases: [String: String] = [
        "postgresql": "psql", "redis": "redis-cli", "python": "python3",
        "openjdk": "java", "sqlite": "sqlite3", "imagemagick": "magick",
        "ripgrep": "rg", "the_silver_searcher": "ag"
    ]

    /// Exact names that are libraries / build helpers / internal shims — not tools you'd launch.
    static let skip: Set<String> = [
        "portaudio", "openssl", "ca-certificates", "readline", "libyaml",
        "pkg-config", "pkgconf", "gmp", "mpfr", "libtool", "libtoolize", "icu4c",
        "zlib", "xz", "lz4", "zstd", "pcre2", "pcre", "gettext", "sqlite",
        "c_rehash", "captoinfo", "infotocap", "tabs", "tic", "toe", "tput", "tset",
        "clear", "reset", "infocmp", "2to3", "idle3", "pydoc3", "wheel",
        "normalizer", "futurize", "pasteurize", "chardetect", "distro",
        "glow-completion", "x86_64-w64-mingw32-gcc", "update-mime-database",
        "openssl3", "krb5-config", "freetype-config", "gpg-error", "gpgrt-config"
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

    /// True for names that are clearly not user-facing tools (libs, *-config helpers, single
    /// letters, version-suffixed dupes). Keeps the grid full of real tools without coreutils noise.
    static func shouldSkip(_ cmd: String) -> Bool {
        if skip.contains(cmd) { return true }
        if cmd.count < 2 { return true }                                  // `[`, `x`, …
        if cmd.hasSuffix("-config") { return true }                       // pcre2-config, sdl2-config
        if cmd.hasPrefix("lib") && cmd != "libreoffice" { return true }   // libpng16, libtool, …
        if cmd.hasPrefix("_") { return true }
        if cmd.contains(".") { return true }                              // foo.bak, foo.dylib
        return false
    }

    /// Every directory we scan for executables. Built from the login shell's real
    /// PATH (a GUI app doesn't inherit it) plus every common installer/version-manager
    /// location — so anything a developer installs is found, whatever put it there.
    static func scanDirs() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var dirs = Set<String>()

        // The user's real login PATH — covers brew, npm, pipx, cargo, go, custom dirs, …
        let shellPath = run("/bin/zsh", ["-lc", "printf %s \"$PATH\""])
        dirs.formUnion(shellPath.split(separator: ":").map(String.init))

        // Known locations, in case they aren't on PATH for this GUI session.
        dirs.formUnion([
            "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/local/sbin",
            "/opt/local/bin", "/opt/local/sbin",                                   // MacPorts
            "\(home)/.local/bin", "\(home)/bin", "\(home)/.bin",
            "\(home)/.cargo/bin", "\(home)/go/bin", "\(home)/.bun/bin", "\(home)/.deno/bin",
            "\(home)/.npm-global/bin", "\(home)/.yarn/bin", "\(home)/Library/pnpm",
            "\(home)/.dotnet/tools", "\(home)/.composer/vendor/bin", "\(home)/.cabal/bin",
            "\(home)/.mix/escripts", "\(home)/.rye/shims", "\(home)/.modular/bin",
            // version-manager shims
            "\(home)/.local/share/mise/shims", "\(home)/.asdf/shims", "\(home)/.volta/bin",
            "\(home)/.rbenv/shims", "\(home)/.pyenv/shims", "\(home)/.nodenv/shims",
            "\(home)/.local/share/aquaproj-aqua/bin"
        ])

        // Never scan the macOS base bins — they'd flood the grid with coreutils (ls, cat, …).
        dirs.subtract(["/usr/bin", "/bin", "/usr/sbin", "/sbin", "/var/run", ""])
        return Array(dirs)
    }

    /// Returns discovered tools as Agents, excluding any command already covered by curated agents.
    static func tools(excluding curated: Set<String>) -> [Agent] {
        let fm = FileManager.default

        // Collect every executable across all scan dirs (parallel dir reads).
        let group = DispatchGroup()
        let lock = NSLock()
        var names = Set<String>()
        for dir in scanDirs() {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                guard let items = try? fm.contentsOfDirectory(atPath: dir) else { return }
                var found: [String] = []
                for f in items where !f.hasPrefix(".") {
                    if fm.isExecutableFile(atPath: "\(dir)/\(f)") { found.append(f) }
                }
                lock.lock(); names.formUnion(found); lock.unlock()
            }
        }
        group.wait()

        var seen = Set<String>()
        var out: [Agent] = []
        for raw in names.sorted() {
            // strip @version (e.g. node@20), apply formula→binary aliases
            var name = raw
            if let at = name.firstIndex(of: "@") { name = String(name[..<at]) }
            let cmd = aliases[name] ?? name
            if shouldSkip(cmd) || curated.contains(cmd) || seen.contains(cmd) { continue }
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
