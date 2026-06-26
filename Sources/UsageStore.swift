import SwiftUI

/// Persists pinned favorites and launch counts (for frequency sorting). Keyed by agent name.
@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()

    @Published private(set) var pinned: Set<String> = []
    @Published private(set) var counts: [String: Int] = [:]
    @Published private(set) var recentDirs: [String] = []

    private let d = UserDefaults.standard

    init() {
        pinned = Set(d.stringArray(forKey: "pinnedAgents") ?? [])
        counts = (d.dictionary(forKey: "launchCounts") as? [String: Int]) ?? [:]
        recentDirs = d.stringArray(forKey: "recentDirs") ?? []
    }

    func addRecentDir(_ path: String) {
        var r = recentDirs.filter { $0 != path }
        r.insert(path, at: 0)
        recentDirs = Array(r.prefix(8))
        d.set(recentDirs, forKey: "recentDirs")
    }

    func isPinned(_ name: String) -> Bool { pinned.contains(name) }

    func togglePin(_ name: String) {
        if pinned.contains(name) { pinned.remove(name) } else { pinned.insert(name) }
        d.set(Array(pinned), forKey: "pinnedAgents")
    }

    func recordLaunch(_ name: String) {
        counts[name, default: 0] += 1
        d.set(counts, forKey: "launchCounts")
    }

    func count(_ name: String) -> Int { counts[name] ?? 0 }
}
