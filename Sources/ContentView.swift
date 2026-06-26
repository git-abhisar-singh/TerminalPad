import SwiftUI

struct ContentView: View {
    @StateObject private var logos = LogoStore.shared
    @State private var curated: [Agent] = ConfigStore.load()
    @State private var discovered: [Agent] = []
    @State private var query = ""
    @State private var selection = 0
    @State private var popoverAgent: Agent? = nil
    @FocusState private var searchFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 138, maximum: 164), spacing: 26)]

    private var all: [Agent] { curated + discovered }

    private func score(_ a: Agent, _ q: String) -> Int {
        let n = a.name.lowercased()
        if n == q { return 0 }
        if n.hasPrefix(q) { return 1 }
        if n.contains(q) { return 2 }
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
            GlassBackground().ignoresSafeArea()
            Color.black.opacity(0.12).ignoresSafeArea()

            VStack(spacing: 0) {
                searchBar
                Divider().opacity(0.12)
                content
            }
        }
        .frame(minWidth: 780, minHeight: 560)
        .preferredColorScheme(.dark)
        .task { await loadDiscovered() }
        .onChange(of: query) { _, _ in selection = 0 }
        .onAppear { DispatchQueue.main.async { searchFocused = true } }
    }

    // MARK: search

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search agents and tools…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .regular))
                .focused($searchFocused)
                .onSubmit(launchSelected)
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow)   { move(-1); return .handled }
                .onKeyPress(.escape)    { if query.isEmpty { NSApp.keyWindow?.close() } else { query = "" }; return .handled }
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            Button { reload() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Rescan installed tools")
        }
        .padding(.horizontal, 24).padding(.vertical, 18)
    }

    // MARK: content

    @ViewBuilder private var content: some View {
        if query.isEmpty {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 26) {
                    ForEach(all) { agent in
                        AgentTile(agent: agent, logos: logos) { tapped in
                            if tapped.variants.count <= 1 {
                                tapped.variants.first.map { Launcher.launch($0.command) }
                            } else { popoverAgent = tapped }
                        }
                        .popover(isPresented: Binding(
                            get: { popoverAgent == agent },
                            set: { if !$0 { popoverAgent = nil } })) {
                            VariantPicker(agent: agent, logos: logos) { v in
                                popoverAgent = nil; Launcher.launch(v.command)
                            }
                        }
                    }
                }
                .padding(.horizontal, 34).padding(.vertical, 28)
            }
        } else if results.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 34, weight: .light)).foregroundStyle(.white.opacity(0.3))
                Text("No agents or tools match “\(query)”")
                    .font(.system(size: 14)).foregroundStyle(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { i, agent in
                            ResultRow(agent: agent, logos: logos, selected: i == selection)
                                .id(i)
                                .onTapGesture { selection = i; launchSelected() }
                                .onHover { if $0 { selection = i } }
                        }
                    }
                    .padding(12)
                }
                .onChange(of: selection) { _, s in withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(s, anchor: .center) } }
            }
        }
    }

    // MARK: actions

    private func move(_ d: Int) {
        guard !results.isEmpty else { return }
        selection = max(0, min(results.count - 1, selection + d))
    }

    private func launchSelected() {
        let list = results
        guard list.indices.contains(selection), let v = list[selection].variants.first else { return }
        Launcher.launch(v.command)
        NSApp.keyWindow?.close()
    }

    private func reload() {
        curated = ConfigStore.load()
        Task { await loadDiscovered() }
    }

    private func loadDiscovered() async {
        let curatedCmds = Set(curated.flatMap { $0.variants.map { v in
            v.command.split(separator: " ").first.map(String.init) ?? v.command } })
        let found = await Task.detached(priority: .userInitiated) {
            Discovery.tools(excluding: curatedCmds)
        }.value
        await MainActor.run { discovered = found }
    }
}

// MARK: - Shared icon

struct AgentIcon: View {
    let agent: Agent
    @ObservedObject var logos: LogoStore
    var size: CGFloat = 96

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(agent.swiftColor.opacity(0.78).gradient)
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
            if let img = logos.image(for: agent.logo) {
                Image(nsImage: img).resizable().scaledToFit()
                    .padding(size * 0.24)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            } else {
                Text(agent.icon)
                    .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .iconGlass(tint: agent.swiftColor)
    }
}

// MARK: - Grid tile

struct AgentTile: View {
    let agent: Agent
    @ObservedObject var logos: LogoStore
    let onTap: (Agent) -> Void
    @State private var hover = false

    var body: some View {
        Button { onTap(agent) } label: {
            VStack(spacing: 11) {
                AgentIcon(agent: agent, logos: logos, size: 94)
                    .shadow(color: agent.swiftColor.opacity(hover ? 0.5 : 0.28), radius: hover ? 17 : 9, y: 5)
                    .scaleEffect(hover ? 1.06 : 1.0)
                VStack(spacing: 2) {
                    Text(agent.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95)).lineLimit(1)
                    Text(agent.discovered ? "tool"
                         : agent.variants.count == 1 ? "1 mode" : "\(agent.variants.count) modes")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                }
            }
            .frame(width: 138)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.spring(response: 0.26, dampingFraction: 0.68), value: hover)
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
                Text(agent.name).font(.system(size: 15, weight: .semibold))
                Text(agent.variants.first?.command ?? "")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45)).lineLimit(1)
            }
            Spacer()
            if agent.variants.count > 1 {
                Text("\(agent.variants.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(.white.opacity(0.1), in: Capsule())
            }
            Image(systemName: "return")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(selected ? 0.85 : 0.0))
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
    @ViewBuilder func iconGlass(tint: Color) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.tint(tint.opacity(0.22)).interactive(),
                             in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        } else { self }
    }
}

struct GlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .vibrantDark)
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}
