import SwiftUI
import AppKit
import CoreImage

/// Resolves a logo image for a slug: bundled -> on-disk cache -> async fetch (simpleicons).
/// Falls back to nil (caller draws a monogram) when no logo exists.
@MainActor
final class LogoStore: ObservableObject {
    static let shared = LogoStore()

    @Published private(set) var images: [String: NSImage] = [:]
    private var tried = Set<String>()

    private var cacheDir: URL {
        let d = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/agentpad/logos", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func image(for slug: String?) -> NSImage? {
        guard let slug, !slug.isEmpty else { return nil }
        if let img = images[slug] { return img }

        // bundled
        if let url = Bundle.main.resourceURL?.appendingPathComponent("logos/\(slug).png"),
           let img = NSImage(contentsOf: url) {
            images[slug] = img
            return img
        }
        // cache
        let cached = cacheDir.appendingPathComponent("\(slug).png")
        if let img = NSImage(contentsOf: cached) {
            images[slug] = img
            return img
        }
        // fetch once
        if !tried.contains(slug) {
            tried.insert(slug)
            Task.detached(priority: .utility) { await Self.fetch(slug: slug, into: cached) { img in
                await MainActor.run { self.images[slug] = img }
            } }
        }
        return nil
    }

    nonisolated static func fetch(slug: String, into dest: URL, done: @escaping (NSImage) async -> Void) async {
        guard let url = URL(string: "https://cdn.simpleicons.org/\(slug)/000000"),
              let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let svg = String(data: data, encoding: .utf8), svg.contains("<svg")
        else { return }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ap_\(slug)_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let svgURL = tmp.appendingPathComponent("i.svg")
        try? data.write(to: svgURL)

        // rasterize black-on-white via QuickLook
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        p.arguments = ["-t", "-s", "512", "-o", tmp.path, svgURL.path]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()

        let raster = tmp.appendingPathComponent("i.svg.png")
        guard let ci = CIImage(contentsOf: raster) else { return }

        // black logo on white -> invert -> mask-to-alpha = white logo on transparent
        guard let inv = CIFilter(name: "CIColorInvert", parameters: [kCIInputImageKey: ci])?.outputImage,
              let masked = CIFilter(name: "CIMaskToAlpha", parameters: [kCIInputImageKey: inv])?.outputImage
        else { return }

        let ctx = CIContext()
        guard let cg = ctx.createCGImage(masked, from: masked.extent) else { return }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: dest)
        try? FileManager.default.removeItem(at: tmp)

        let img = NSImage(size: NSSize(width: cg.width, height: cg.height))
        img.addRepresentation(rep)
        await done(img)
    }
}
