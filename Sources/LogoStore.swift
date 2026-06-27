import SwiftUI
import AppKit
import CoreImage

/// Loads logos OFF the main thread and publishes them in batches.
/// Views call `image(_:)` — a pure dictionary read, never mutated during `body`.
@MainActor
final class LogoStore: ObservableObject {
    static let shared = LogoStore()

    @Published private(set) var images: [String: NSImage] = [:]
    private var inFlight = Set<String>()

    nonisolated private static let bundledDir = Bundle.main.resourceURL?.appendingPathComponent("logos")
    nonisolated private static var cacheDir: URL {
        let d = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/terminalpad/logos", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Pure read — safe to call from `body`.
    func image(_ slug: String?) -> NSImage? {
        guard let slug else { return nil }
        return images[slug]
    }

    /// Load any not-yet-loaded slugs in the background, publish in one batch, then fetch the rest online.
    func preload(_ slugs: [String]) {
        let missing = slugs.filter { !$0.isEmpty && images[$0] == nil && !inFlight.contains($0) }
        guard !missing.isEmpty else { return }
        missing.forEach { inFlight.insert($0) }

        Task.detached(priority: .utility) {
            var loaded: [String: NSImage] = [:]
            var needFetch: [String] = []
            for slug in missing {
                if let url = Self.bundledDir?.appendingPathComponent("\(slug).png"),
                   let img = NSImage(contentsOf: url) {
                    loaded[slug] = img
                } else if let img = NSImage(contentsOf: Self.cacheDir.appendingPathComponent("\(slug).png")) {
                    loaded[slug] = img
                } else {
                    needFetch.append(slug)
                }
            }
            let snapshot = loaded
            await MainActor.run {
                for (k, v) in snapshot { self.images[k] = v }
                snapshot.keys.forEach { self.inFlight.remove($0) }
            }
            for slug in needFetch {
                if let img = await Self.fetch(slug: slug) {
                    await MainActor.run { self.images[slug] = img; self.inFlight.remove(slug) }
                } else {
                    await MainActor.run { self.inFlight.remove(slug) }
                }
            }
        }
    }

    /// Download a Simple Icons mark, rasterize via qlmanage, key white->transparent. Returns nil on miss.
    nonisolated static func fetch(slug: String) async -> NSImage? {
        guard let url = URL(string: "https://cdn.simpleicons.org/\(slug)/000000"),
              let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let svg = String(data: data, encoding: .utf8), svg.contains("<svg")
        else { return nil }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ap_\(slug)_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let svgURL = tmp.appendingPathComponent("i.svg")
        try? data.write(to: svgURL)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        p.arguments = ["-t", "-s", "256", "-o", tmp.path, svgURL.path]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()

        let raster = tmp.appendingPathComponent("i.svg.png")
        guard let ci = CIImage(contentsOf: raster),
              let inv = CIFilter(name: "CIColorInvert", parameters: [kCIInputImageKey: ci])?.outputImage,
              let masked = CIFilter(name: "CIMaskToAlpha", parameters: [kCIInputImageKey: inv])?.outputImage,
              let cg = CIContext().createCGImage(masked, from: masked.extent)
        else { return nil }

        let rep = NSBitmapImageRep(cgImage: cg)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: cacheDir.appendingPathComponent("\(slug).png"))
        }
        let img = NSImage(size: NSSize(width: cg.width, height: cg.height))
        img.addRepresentation(rep)
        return img
    }
}
