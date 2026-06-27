import SwiftUI

struct ContentView: View {
    @StateObject private var logos = LogoStore.shared
    @StateObject private var usage = UsageStore.shared
    @State private var curated: [Agent] = ConfigStore.load()
    @State private var discovered: [Agent] = []
    @State private var query = ""
    @State private var selection = 0
    @State private var popoverAgent: Agent? = nil
    @FocusState private var searchFocused: Bool
    @AppStorage("showDiscovered") private var showDiscovered = true
    @AppStorage("quitAfterLaunch") private var quitAfterLaunch = true
    @AppStorage("glassBlur") private var glassBlur = true
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("rescanOnLaunch") private var rescanOnLaunch = true
    @AppStorage("seenOnboarding") private var seenOnboarding = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var showSettings = false
    @State private var launchToast: String? = nil
    @State private var helpText: String? = nil
    @State private var helpTitle = ""
    @State private var gridCols = 5

    private var isDark: Bool {
        switch appearance { case "light": return false; case "dark": return true
        default: return colorScheme == .dark }
    }
    private var scheme: ColorScheme? {
        switch appearance { case "light": return .light; case "dark": return .dark; default: return nil }
    }

    private let columns = [GridItem(.adaptive(minimum: 130, maximum: 156), spacing: 18)]

    private var all: [Agent] { showDiscovered ? curated + discovered : curated }

    private func run(_ agent: Agent, _ command: String, cwd: String? = nil) {
        usage.recordLaunch(agent.name)
        Launcher.launch(command, cwd: cwd ?? agent.cwd)
        withAnimation { launchToast = agent.name }
        if quitAfterLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSApp.hide(nil) }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                if launchToast == agent.name { withAnimation { launchToast = nil } }
            }
        }
    }

    private func pickFolderAndRun(_ agent: Agent, _ command: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Run Here"
        panel.message = "Choose a folder to run \(agent.name) in"
        if panel.runModal() == .OK, let url = panel.url {
            usage.addRecentDir(url.path)
            run(agent, command, cwd: url.path)
        }
    }

    private func showHelp(_ agent: Agent) {
        guard let base = agent.variants.first?.command.split(separator: " ").first.map(String.init) else { return }
        helpTitle = agent.name
        helpText = "Loading…"
        Task.detached(priority: .userInitiated) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-lc", "\(base) --help 2>&1 | head -250"]
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
            try? p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let out = String(data: data, encoding: .utf8) ?? ""
            await MainActor.run { helpText = out.isEmpty ? "No help output." : out }
        }
    }

    private func score(_ a: Agent, _ q: String) -> Int {
        let n = a.name.lowercased()
        if n == q || a.aliases.contains(where: { $0.lowercased() == q }) { return 0 }
        if n.hasPrefix(q) || a.aliases.contains(where: { $0.lowercased().hasPrefix(q) }) { return 1 }
        if n.contains(q) || a.aliases.contains(where: { $0.lowercased().contains(q) }) { return 2 }
        if a.variants.contains(where: { $0.label.lowercased().contains(q) }) { return 3 }
        if a.variants.contains(where: { $0.command.lowercased().contains(q) }) { return 4 }
        return 99
    }

    private var results: [Agent] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        var scored: [(agent: Agent, rank: Int)] = []
        for a in all {
            let r = score(a, q)
            if r < 99 { scored.append((a, r)) }
        }
        scored.sort { lhs, rhs in
            lhs.rank != rhs.rank ? lhs.rank < rhs.rank
                                 : lhs.agent.name.lowercased() < rhs.agent.name.lowercased()
        }
        return scored.map { $0.agent }
    }

    var body: some View {
        ZStack {
            if glassBlur {
                GlassBackground(dark: isDark)   // live desktop blur
                // Control-Center-style tint, darker toward the bottom
                LinearGradient(colors: isDark ? [Color.black.opacity(0.32), Color.black.opacity(0.5)]
                                               : [Color.white.opacity(0.4), Color.white.opacity(0.62)],
                               startPoint: .top, endPoint: .bottom)
            } else {
                LinearGradient(colors: isDark ? [Color(white: 0.12), Color(white: 0.04)]
                                              : [Color(white: 0.99), Color(white: 0.93)],
                               startPoint: .top, endPoint: .bottom)
            }
            VStack(spacing: 0) {
                titleBar
                if showSettings {
                    settingsHeader
                    SettingsView()
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    Button("") { withAnimation(.easeInOut(duration: 0.2)) { showSettings = false } }
                        .keyboardShortcut(.cancelAction).hidden().frame(width: 0, height: 0)
                } else {
                    searchRow
                    content
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .frame(minWidth: 780, minHeight: 560)
        .preferredColorScheme(scheme)
        .task { if rescanOnLaunch { await loadDiscovered() } }
        .onChange(of: query) { _, _ in selection = 0 }
        .onChange(of: showSettings) { _, s in
            if !s { DispatchQueue.main.async { searchFocused = true } }
        }
        .onAppear {
            logos.preload(curated.compactMap { $0.logo })
            DispatchQueue.main.async { searchFocused = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentpadReload)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            DispatchQueue.main.async { searchFocused = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentpadFocusSearch)) { _ in
            query = ""; DispatchQueue.main.async { searchFocused = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentpadOpenSettings)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { showSettings = true }
        }
        .sheet(isPresented: Binding(get: { helpText != nil }, set: { if !$0 { helpText = nil } })) {
            HelpSheet(title: helpTitle, text: helpText ?? "") { helpText = nil }
        }
        .overlay(alignment: .bottom) {
            if let t = launchToast {
                Label("Launching \(t)…", systemImage: "terminal")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.primary.opacity(0.12), lineWidth: 1))
                    .padding(.bottom, 26)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: search

    // Notes-style toolbar: identity by the traffic lights, controls on the right.
    // Fixed-height strip so content vertically centres with the native traffic lights.
    private var titleBar: some View {
        // Title only — this region overlaps the draggable titlebar, so NO buttons here.
        Text(showSettings ? "Settings" : "AgentPad")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)          // matches the unified titlebar; lights centre here
    }

    // Controls live BELOW the titlebar so clicks aren't eaten by the window-drag region.
    private var searchRow: some View {
        HStack(spacing: 10) {
            searchField
            headerButton("arrow.clockwise", help: "Rescan installed tools") { reload() }
            headerButton("gearshape", help: "Settings") {
                withAnimation(.easeInOut(duration: 0.2)) { showSettings = true }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    private var settingsHeader: some View {
        HStack {
            Button { withAnimation(.easeInOut(duration: 0.2)) { showSettings = false } } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(.primary.opacity(0.12), lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .help("Back")
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search agents and tools…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .regular))
                .focused($searchFocused)
                .onSubmit(launchSelected)
                .onKeyPress(.downArrow)  { selectRow(1); return .handled }
                .onKeyPress(.upArrow)    { selectRow(-1); return .handled }
                .onKeyPress(.leftArrow)  { if query.isEmpty { selectStep(-1); return .handled }; return .ignored }
                .onKeyPress(.rightArrow) { if query.isEmpty { selectStep(1); return .handled }; return .ignored }
                .onKeyPress(.escape)     { if query.isEmpty { NSApp.hide(nil) } else { query = "" }; return .handled }
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background((isDark ? Color.white : Color.black).opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder((isDark ? Color.white : Color.black).opacity(0.06), lineWidth: 1))
    }

    private func headerButton(_ symbol: String, help: String = "", action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }

    // MARK: content

    @ViewBuilder private var content: some View {
        if query.isEmpty {
            let favs = sortedByUse(all.filter { usage.isPinned($0.name) })
            let ags = sortedByUse(curated)
            let tools = showDiscovered ? sortedByUse(discovered) : []
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            if !seenOnboarding { onboardingCard }
                            if !favs.isEmpty { section("Favorites", favs, base: 0) }
                            section("Agents", ags, base: favs.count)
                            if !tools.isEmpty { section("Tools", tools, base: favs.count + ags.count) }
                        }
                        .padding(.horizontal, 30).padding(.top, 14).padding(.bottom, 40)
                    }
                    .bottomFade()
                    .onChange(of: geo.size.width) { _, w in updateCols(w) }
                    .onAppear { updateCols(geo.size.width) }
                    .onChange(of: selection) { _, s in
                        guard gridAgents.indices.contains(s) else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(gridAgents[s].id, anchor: .center)
                        }
                    }
                }
            }
        } else if results.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 34, weight: .light)).foregroundStyle(.secondary)
                Text("No agents or tools match “\(query)”")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { i, agent in
                            ResultRow(agent: agent, logos: logos, selected: i == selection)
                                .id(agent.id)
                                .onTapGesture { selection = i; launchSelected() }
                                .onHover { if $0 { selection = i } }
                        }
                    }
                    .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 24)
                }
                .bottomFade()
                .onChange(of: selection) { _, s in
                    guard results.indices.contains(s) else { return }
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(results[s].id, anchor: .center) }
                }
            }
        }
    }

    private func sortedByUse(_ items: [Agent]) -> [Agent] {
        items.enumerated().sorted { l, r in
            let cl = usage.count(l.element.name), cr = usage.count(r.element.name)
            return cl != cr ? cl > cr : l.offset < r.offset
        }.map { $0.element }
    }

    /// Flattened grid order (must match the section render order) for keyboard nav.
    private var gridAgents: [Agent] {
        let favs = sortedByUse(all.filter { usage.isPinned($0.name) })
        let tools = showDiscovered ? sortedByUse(discovered) : []
        return favs + sortedByUse(curated) + tools
    }

    private func updateCols(_ width: CGFloat) {
        let cols = max(1, Int((width - 60) / 148))
        if cols != gridCols { gridCols = cols }
    }

    private var onboardingCard: some View {
        HStack(alignment: .top, spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Welcome to AgentPad").font(.system(size: 12.5, weight: .semibold))
                Text("A launcher for your terminal agents and CLI tools. Click any tile to open it in your terminal, or type to search and press Return.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button { withAnimation { seenOnboarding = true } } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background((isDark ? Color.white : Color.black).opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.08), lineWidth: 1))
    }

    @ViewBuilder private func section(_ title: String, _ items: [Agent], base: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold)).tracking(0.9)
                    .foregroundStyle(.secondary)
                Rectangle()
                    .fill((isDark ? Color.white : Color.black).opacity(0.08))
                    .frame(height: 1)
            }
            .padding(.horizontal, 6)
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, agent in
                    tile(agent, index: base + i)
                }
            }
        }
    }

    private func tile(_ agent: Agent, index: Int) -> some View {
        AgentTile(agent: agent, logos: logos,
                  pinned: usage.isPinned(agent.name),
                  selected: query.isEmpty && index == selection) { tapped in
            if tapped.variants.count <= 1 {
                tapped.variants.first.map { run(tapped, $0.command, cwd: $0.cwd) }
            } else { popoverAgent = tapped }
        }
        .contextMenu {
            Button(usage.isPinned(agent.name) ? "Unpin" : "Pin to Favorites") {
                usage.togglePin(agent.name)
            }
            if let v = agent.variants.first {
                Button("Run in Folder…") { pickFolderAndRun(agent, v.command) }
                if !usage.recentDirs.isEmpty {
                    Menu("Recent Folders") {
                        ForEach(usage.recentDirs, id: \.self) { dir in
                            Button((dir as NSString).abbreviatingWithTildeInPath) {
                                usage.addRecentDir(dir); run(agent, v.command, cwd: dir)
                            }
                        }
                    }
                }
                Divider()
                Button("Quick Help (--help)") { showHelp(agent) }
                Button("Copy command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(v.command, forType: .string)
                }
            }
        }
        .popover(isPresented: Binding(
            get: { popoverAgent == agent },
            set: { if !$0 { popoverAgent = nil } })) {
            VariantPicker(agent: agent, logos: logos) { v in
                popoverAgent = nil; run(agent, v.command, cwd: v.cwd)
            }
        }
    }

    // MARK: actions

    private func selectStep(_ d: Int) {   // left/right (or list up/down)
        let count = query.isEmpty ? gridAgents.count : results.count
        guard count > 0 else { return }
        selection = max(0, min(count - 1, selection + d))
    }

    private func selectRow(_ d: Int) {    // up/down
        if query.isEmpty {
            let count = gridAgents.count
            guard count > 0 else { return }
            selection = max(0, min(count - 1, selection + d * gridCols))
        } else { selectStep(d) }
    }

    private func launchSelected() {
        let list = query.isEmpty ? gridAgents : results
        guard list.indices.contains(selection), let v = list[selection].variants.first else { return }
        run(list[selection], v.command, cwd: v.cwd)
    }

    private func reload() {
        curated = ConfigStore.load()
        Task { await loadDiscovered() }
    }

    private func loadDiscovered() async {
        // 1. Paint the last scan instantly (0ms) so tiles never start empty.
        if discovered.isEmpty {
            let cached = DiscoveryCache.load()
            if !cached.isEmpty {
                discovered = cached
                logos.preload(cached.compactMap { $0.logo })
            }
        }
        // 2. Rescan off-main, update + persist only if the tool set actually changed.
        let curatedCmds = Set(curated.flatMap { $0.variants.map { v in
            v.command.split(separator: " ").first.map(String.init) ?? v.command } })
        let found = await Task.detached(priority: .userInitiated) {
            Discovery.tools(excluding: curatedCmds)
        }.value
        let changed = found.map(\.name) != discovered.map(\.name)
        await MainActor.run {
            if changed {
                discovered = found
                logos.preload(found.compactMap { $0.logo })
            }
        }
        if changed { DiscoveryCache.save(found) }
    }
}

// MARK: - Shared icon

struct AgentIcon: View {
    let agent: Agent
    @ObservedObject var logos: LogoStore
    var size: CGFloat = 96
    @Environment(\.colorScheme) private var scheme

    private var dark: Bool { scheme == .dark }

    // Dark: vivid brand tile + white mark. Light: soft light tile + brand-coloured mark.
    private var tileFill: AnyShapeStyle {
        dark ? AnyShapeStyle(agent.swiftColor.opacity(0.85).gradient)
             : AnyShapeStyle(LinearGradient(colors: [Color.white, Color(white: 0.93)],
                                            startPoint: .top, endPoint: .bottom))
    }
    private var mark: Color { dark ? .white : agent.swiftColor }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(tileFill)
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .stroke((dark ? Color.white : Color.black).opacity(0.12), lineWidth: 1)
            if let img = logos.image(agent.logo) {
                Image(nsImage: img).renderingMode(.template).resizable().scaledToFit()
                    .padding(size * 0.24)
                    .foregroundStyle(mark)
            } else {
                Text(agent.icon)
                    .font(.system(size: size * 0.30, weight: .semibold))
                    .foregroundStyle(mark)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Grid tile

struct AgentTile: View {
    let agent: Agent
    @ObservedObject var logos: LogoStore
    var pinned: Bool = false
    var selected: Bool = false
    let onTap: (Agent) -> Void
    @State private var hover = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button { onTap(agent) } label: {
            VStack(spacing: 11) {
                AgentIcon(agent: agent, logos: logos, size: 92)
                    .overlay(alignment: .topTrailing) {
                        if pinned {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.yellow)
                                .padding(5)
                                .background(.ultraThinMaterial, in: Circle())
                                .offset(x: 7, y: -7)
                        }
                    }
                    // glow only on the hovered tile (1 tile = cheap, no scroll lag)
                    .shadow(color: agent.swiftColor.opacity(hover ? 0.55 : 0),
                            radius: hover ? 18 : 0, y: 5)
                VStack(spacing: 2) {
                    Text(agent.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary).lineLimit(1)
                    Text(agent.discovered ? "tool"
                         : agent.variants.count == 1 ? "1 mode" : "\(agent.variants.count) modes")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 132)
            .padding(.top, 12).padding(.bottom, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill((scheme == .dark ? Color.white : Color.black).opacity(hover || selected ? 0.07 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(agent.swiftColor.opacity(selected ? 0.9 : 0), lineWidth: 2)
            )
            .offset(y: hover ? -3 : 0)
            .scaleEffect(hover ? 1.04 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { h in
            if h && !hover { Haptics.tick() }   // gentle tick on hover-enter only
            hover = h
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: hover)
    }
}

// MARK: - Spotlight result row

struct ResultRow: View {
    let agent: Agent
    @ObservedObject var logos: LogoStore
    let selected: Bool

    var body: some View {
        HStack(spacing: 14) {
            AgentIcon(agent: agent, logos: logos, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                Text(agent.variants.first?.command ?? "")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if agent.variants.count > 1 {
                Text("\(agent.variants.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(.primary.opacity(0.08), in: Capsule())
            }
            Image(systemName: "return")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.primary.opacity(selected ? 0.85 : 0.0))
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(selected ? AnyShapeStyle(agent.swiftColor.opacity(0.22)) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(selected ? 0.14 : 0), lineWidth: 1))
        .contentShape(Rectangle())
    }
}

// MARK: - Variant popover

struct VariantPicker: View {
    let agent: Agent
    @ObservedObject var logos: LogoStore
    let onPick: (Variant) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                AgentIcon(agent: agent, logos: logos, size: 26)
                Text(agent.name).font(.system(size: 13, weight: .bold))
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 2)

            ForEach(agent.variants) { v in
                VariantRow(variant: v) { onPick(v) }
            }
        }
        .padding(.bottom, 10).frame(width: 280).preferredColorScheme(.dark)
    }
}

struct VariantRow: View {
    let variant: Variant
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(variant.swiftColor.opacity(0.9).gradient).frame(width: 32, height: 32)
                    Image(systemName: variant.icon)
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(variant.label).font(.system(size: 13.5, weight: .semibold))
                    Text(variant.command)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(hover ? 0.9 : 0.3))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(hover ? .white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).padding(.horizontal, 8).onHover { hover = $0 }
    }
}

// MARK: - Glass

extension View {
    /// Fades the very bottom edge of scrolling content to transparent (no hard cut), bg-agnostic.
    func bottomFade(_ h: CGFloat = 26) -> some View {
        mask(
            VStack(spacing: 0) {
                Rectangle().fill(.black)
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: h)
            }
        )
    }

    @ViewBuilder func iconGlass(tint: Color) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.tint(tint.opacity(0.22)),
                             in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        } else { self }
    }
}

/// Haptic tick on Force Touch trackpads (no-op on hardware without haptics).
/// Strength comes from the "hapticLevel" setting: off / light / medium / strong.
enum Haptics {
    static func tick() {
        let level = UserDefaults.standard.string(forKey: "hapticLevel") ?? "strong"
        let pattern: NSHapticFeedbackManager.FeedbackPattern?
        switch level {
        case "off":    pattern = nil
        case "light":  pattern = .alignment
        case "medium": pattern = .generic
        default:       pattern = .levelChange   // strong
        }
        if let pattern {
            NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
        }
    }
}

struct HelpSheet: View {
    let title: String
    let text: String
    let onDone: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(title) — help").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Done", action: onDone).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            ScrollView {
                Text(text)
                    .font(.system(size: 11.5, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        }
        .frame(width: 560, height: 460)
    }
}

struct GlassBackground: NSViewRepresentable {
    var dark: Bool = true

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.state = .active
        apply(v)
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { apply(v) }

    private func apply(_ v: NSVisualEffectView) {
        v.material = dark ? .hudWindow : .popover
        v.appearance = NSAppearance(named: dark ? .vibrantDark : .vibrantLight)
    }
}
