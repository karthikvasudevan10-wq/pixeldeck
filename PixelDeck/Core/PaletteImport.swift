import Foundation

/// Reads palette files from other apps and sites (Lospec, Aseprite, GIMP, Paint.NET):
/// - `.hex`: one RRGGBB per line (`#` optional)
/// - `.gpl`: GIMP palette ("R G B name" lines, a "Name:" header)
/// - `.txt`: Paint.NET (AARRGGBB per line, `;` comments)
/// Palette images (.png) are read in the app layer and passed to `sets`.
/// Pixel Deck palettes have 10 colours, so a bigger palette becomes several saved palettes.
enum PaletteImport {
    /// More than this many colours are ignored (8 saved palettes).
    static let maxColors = 80

    struct Parsed: Equatable {
        var name: String?
        var colors: [RGBA]
    }

    static func parse(_ data: Data, fileName: String) -> Parsed? {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        let ext = (fileName as NSString).pathExtension.lowercased()
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        var name: String?
        var colors: [RGBA] = []
        if ext == "gpl" || lines.first?.hasPrefix("GIMP Palette") == true {
            for line in lines.dropFirst() {
                if line.lowercased().hasPrefix("name:") {
                    name = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    continue
                }
                guard !line.isEmpty, !line.hasPrefix("#"), !line.lowercased().hasPrefix("columns:") else { continue }
                let parts = line.split(whereSeparator: \.isWhitespace).prefix(3).compactMap { Int($0) }
                guard parts.count == 3, parts.allSatisfy({ (0...255).contains($0) }) else { continue }
                colors.append(RGBA(r: UInt8(parts[0]), g: UInt8(parts[1]), b: UInt8(parts[2])))
            }
        } else {
            for line in lines where !line.isEmpty && !line.hasPrefix(";") && !line.hasPrefix("//") {
                var hex = line.hasPrefix("#") ? String(line.dropFirst()) : line
                hex = String(hex.prefix(while: { $0.isHexDigit }))
                if hex.count == 8 { hex = String(hex.dropFirst(2)) }        // Paint.NET's AARRGGBB
                guard hex.count == 6, let v = UInt32(hex, radix: 16) else { continue }
                colors.append(RGBA(hex: v))
            }
        }
        let unique = dedupe(colors)
        guard !unique.isEmpty else { return nil }
        if name == nil || name!.isEmpty {
            name = ((fileName as NSString).deletingPathExtension as NSString).lastPathComponent
        }
        return Parsed(name: name, colors: Array(unique.prefix(maxColors)))
    }

    /// Splits colours into 10-colour palettes ("Endesga 32 1/4" …). A last, shorter set is
    /// filled by repeating its own colours.
    static func sets(name: String, colors: [RGBA]) -> [(name: String, colors: [RGBA])] {
        let size = SpriteProject.defaultPalette.count
        let list = Array(dedupe(colors).prefix(maxColors))
        guard !list.isEmpty else { return [] }
        let chunks = stride(from: 0, to: list.count, by: size).map { Array(list[$0..<min($0 + size, list.count)]) }
        return chunks.enumerated().map { i, chunk in
            var filled = chunk
            var k = 0
            while filled.count < size { filled.append(chunk[k % chunk.count]); k += 1 }
            let title = chunks.count == 1 ? name : "\(name) \(i + 1)/\(chunks.count)"
            return (title, filled)
        }
    }

    static func dedupe(_ colors: [RGBA]) -> [RGBA] {
        var seen = Set<RGBA>()
        return colors.map { RGBA(r: $0.r, g: $0.g, b: $0.b, a: 255) }.filter { seen.insert($0).inserted }
    }
}
