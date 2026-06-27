import Foundation
import AppKit

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

    /// Homebrew binary dirs, used only to resolve a `brew leaves` formula to its real command.
    static let brewBins = ["/opt/homebrew/bin", "/opt/homebrew/sbin",
                           "/usr/local/bin", "/usr/local/sbin", "/opt/local/bin"]

    /// Resolve a brew formula name to an actual top-level command. Returns nil for
    /// library-only formulae (no runnable binary) so deps never show up.
    static func resolveBrew(_ formula: String) -> String? {
        var name = formula.split(separator: "/").last.map(String.init) ?? formula  // drop tap prefix
        if let at = name.firstIndex(of: "@") { name = String(name[..<at]) }        // drop @version
        for candidate in [aliases[name] ?? name, name] {
            for dir in brewBins where FileManager.default.isExecutableFile(atPath: "\(dir)/\(candidate)") {
                return candidate
            }
        }
        return nil
    }

    /// Every executable name available on the system (full PATH incl. system bins) — used only
    /// for *membership* tests like "is this command installed", never for listing in the grid.
    static func installedCommands() -> Set<String> {
        let fm = FileManager.default
        var dirs = Set<String>()
        let shellPath = run("/bin/zsh", ["-lc", "printf %s \"$PATH\""])
        dirs.formUnion(shellPath.split(separator: ":").map(String.init))
        dirs.formUnion(brewBins)
        dirs.formUnion(userBinDirs())
        dirs.formUnion(["/usr/bin", "/bin", "/usr/sbin", "/sbin"])
        var set = Set<String>()
        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for f in items where !f.hasPrefix(".") { set.insert(f) }
        }
        return set
    }

    static func firstWord(_ cmd: String) -> String { cmd.split(separator: " ").first.map(String.init) ?? cmd }

    /// True if a GUI app with this name is installed (so we can open it when the CLI is absent).
    static func isAppInstalled(_ name: String?) -> Bool {
        guard let name, !name.isEmpty else { return false }
        let bundle = name.hasSuffix(".app") ? name : name + ".app"
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dirs = ["/Applications", "/Applications/Utilities", "\(home)/Applications", "/System/Applications"]
        if dirs.contains(where: { FileManager.default.fileExists(atPath: "\($0)/\(bundle)") }) { return true }
        return NSWorkspace.shared.fullPath(forApplication: name) != nil
    }

    /// An agent counts as installed if its CLI exists OR (for app-backed agents) its GUI app exists.
    static func isInstalled(_ agent: Agent, in set: Set<String>) -> Bool {
        if agent.variants.contains(where: { set.contains(firstWord($0.command)) }) { return true }
        return isAppInstalled(agent.app)
    }

    /// True if the agent's CLI command is actually present (used to decide CLI-vs-app at launch).
    static func hasCLI(_ agent: Agent, in set: Set<String>) -> Bool {
        agent.variants.contains { set.contains(firstWord($0.command)) }
    }

    /// User-owned package/bin dirs. Everything here was installed deliberately by the user
    /// (cargo/go/bun/pipx/pnpm/etc.) — never Homebrew dependency binaries.
    static func userBinDirs() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.local/bin", "\(home)/bin", "\(home)/.cargo/bin", "\(home)/go/bin",
            "\(home)/.bun/bin", "\(home)/.deno/bin", "\(home)/.npm-global/bin",
            "\(home)/.yarn/bin", "\(home)/Library/pnpm", "\(home)/.dotnet/tools",
            "\(home)/.composer/vendor/bin", "\(home)/.cabal/bin", "\(home)/.mix/escripts"
        ]
    }

    /// Returns discovered tools as Agents — only things the user *intentionally* installed:
    /// Homebrew `leaves` (installed-on-request, not dependencies), global npm/pipx packages,
    /// and user-owned bin dirs (cargo/go/bun/…). Never raw Homebrew bin scans (that pulls deps).
    static func tools(excluding curated: Set<String>) -> [Agent] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let group = DispatchGroup()
        let lock = NSLock()
        var names = Set<String>()
        func add(_ items: [String]) { lock.lock(); names.formUnion(items); lock.unlock() }

        // 1. Homebrew formulae installed on request (excludes dependencies), resolved to real commands.
        if let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first(where: { fm.isExecutableFile(atPath: $0) }) {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                add(run(brew, ["leaves"]).split(whereSeparator: \.isNewline)
                    .compactMap { resolveBrew(String($0)) })
            }
        }

        // 2. Global npm packages.
        if let npm = ["/opt/homebrew/bin/npm", "/usr/local/bin/npm"]
            .first(where: { fm.isExecutableFile(atPath: $0) }) {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                add(run(npm, ["ls", "-g", "--depth=0", "--parseable"])
                    .split(whereSeparator: \.isNewline)
                    .compactMap { $0.split(separator: "/").last.map(String.init) }
                    .filter { $0 != "lib" && !$0.hasPrefix("@") })
            }
        }

        // 3. pipx apps.
        if let pipx = ["/opt/homebrew/bin/pipx", "\(home)/.local/bin/pipx"]
            .first(where: { fm.isExecutableFile(atPath: $0) }) {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                add(run(pipx, ["list", "--short"])
                    .split(whereSeparator: \.isNewline)
                    .compactMap { $0.split(separator: " ").first.map(String.init) })
            }
        }

        // 4. User-owned bin dirs (cheap reads, inline).
        for dir in userBinDirs() {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            add(items.filter { !$0.hasPrefix(".") && fm.isExecutableFile(atPath: "\(dir)/\($0)") })
        }

        group.wait()

        var seen = Set<String>()
        var out: [Agent] = []
        for raw in names.sorted() {
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
