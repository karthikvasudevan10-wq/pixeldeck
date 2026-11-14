import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case spriteSheet, gif, frames
    var id: String { rawValue }
}

struct ExportOptions {
    var format: ExportFormat = .spriteSheet
    var layout: SpriteSheetLayout = .strip
    var scale = 1
    var includeMetadata = true
}

enum ExportError: LocalizedError {
    case couldNotWrite(String)
    var errorDescription: String? {
        switch self {
        case .couldNotWrite(let name): String(localized: "Couldn't write \(name).", comment: "Export error; the placeholder is a file name")
        }
    }
}

/// Writes PNG / GIF / JSON files to a temporary folder for sharing.
enum SpriteExporter {
    /// Largest output side we allow, to keep memory sane.
    static let maxSide = 8192

    static func allowedScales(for project: SpriteProject, options: ExportOptions) -> [Int] {
        [1, 2, 4, 8, 16, 32].filter { scale in
            switch options.format {
            case .spriteSheet:
                let s = SpriteSheet.pixelSize(canvas: project.size, frameCount: project.frames.count, scale: scale, layout: options.layout)
                return max(s.width, s.height) <= maxSide
            case .gif, .frames:
                return project.size * scale <= 2048
            }
        }
    }

    static func export(_ project: SpriteProject, options: ExportOptions) throws -> [URL] {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let base = fileSafe(project.name)
        let grids = project.frames.map(\.grid)
        let scale = max(1, options.scale)

        switch options.format {
        case .spriteSheet:
            let sheet = SpriteSheet(grids: grids, scale: scale, layout: options.layout)
            let name = "\(base)_sheet.png"
            let png = dir.appendingPathComponent(name)
            try writePNG(width: sheet.width, height: sheet.height, rgba: sheet.bytes, to: png)
            var urls = [png]
            if options.includeMetadata {
                let json = dir.appendingPathComponent("\(base)_sheet.json")
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(sheet.metadata(fps: project.fps, imageName: name)).write(to: json)
                urls.append(json)
            }
            return urls

        case .gif:
            let url = dir.appendingPathComponent("\(base).gif")
            try writeGIF(grids: grids, scale: scale, fps: project.fps, to: url)
            return [url]

        case .frames:
            return try grids.enumerated().map { i, grid in
                let url = dir.appendingPathComponent(String(format: "%@_%03d.png", base, i + 1))
                let side = grid.size * scale
                try writePNG(width: side, height: side, rgba: grid.rgbaBytes(scale: scale), to: url)
                return url
            }
        }
    }

    static func writePNG(width: Int, height: Int, rgba: [UInt8], to url: URL) throws {
        guard let image = PixelRenderer.cgImage(width: width, height: height, rgba: rgba),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw ExportError.couldNotWrite(url.lastPathComponent) }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw ExportError.couldNotWrite(url.lastPathComponent) }
    }

    static func writeGIF(grids: [PixelGrid], scale: Int, fps: Int, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, grids.count, nil)
        else { throw ExportError.couldNotWrite(url.lastPathComponent) }
        let loop: [String: Any] = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]]
        CGImageDestinationSetProperties(dest, loop as CFDictionary)
        let delay = 1 / Double(max(1, fps))
        let frameProps: [String: Any] = [kCGImagePropertyGIFDictionary as String: [
            kCGImagePropertyGIFDelayTime as String: delay,
            kCGImagePropertyGIFUnclampedDelayTime as String: delay,
        ]]
        for grid in grids {
            guard let image = PixelRenderer.cgImage(grid, scale: scale) else { throw ExportError.couldNotWrite(url.lastPathComponent) }
            CGImageDestinationAddImage(dest, image, frameProps as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { throw ExportError.couldNotWrite(url.lastPathComponent) }
    }

    private static func fileSafe(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let s = String(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return s.isEmpty ? "sprite" : s
    }
}
