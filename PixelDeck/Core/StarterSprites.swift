import Foundation

/// Animations described as character grids (the design handoff's `sprites.json`):
///
///     { "pal": { "k": "#1B1530", … },
///       "slime": { "w": 12, "h": 16, "fps": 8, "frames": [ ["....kkkk....", …], … ] }, … }
///
/// `.` is transparent; any other character is a key into `pal`. Used for the starter sprites in
/// the gallery and the animated characters on the welcome and tutorial screens.
struct CharacterSprite: Sendable {
    let key: String
    let width: Int
    let height: Int
    let fps: Int
    /// One grid per frame, `width`×`height`.
    let frames: [PixelGrid]

    /// Frame for a playback time, looping: floor(time × fps) mod frameCount.
    func frame(at time: TimeInterval) -> PixelGrid {
        let i = Int((time * Double(fps)).rounded(.down)) % frames.count
        return frames[max(0, i)]
    }

    /// A new sprite with these frames, centred on world (0, 0).
    func makeProject(name: String) -> SpriteProject {
        let bounds = PixelRect(x: -width / 2, y: -height / 2, width: width, height: height)
        return SpriteProject(name: name, bounds: bounds, frames: frames, fps: fps)
    }
}

enum CharacterSpriteLibrary {
    /// Order the starter sprites appear in.
    static let order = ["slime", "flame", "coin", "ghost", "sprout", "moon"]

    /// Parses the JSON. Malformed sprites are skipped rather than failing the whole file.
    static func parse(_ data: Data) -> [String: CharacterSprite] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        var palette: [Character: RGBA] = [:]
        for (k, v) in (root["pal"] as? [String: String]) ?? [:] {
            if let ch = k.first, k.count == 1, let c = RGBA(hexString: v) { palette[ch] = c }
        }
        var out: [String: CharacterSprite] = [:]
        for (key, value) in root where key != "pal" {
            guard let d = value as? [String: Any],
                  let w = d["w"] as? Int, let h = d["h"] as? Int, w > 0, h > 0, w <= 256, h <= 256,
                  let rawFrames = d["frames"] as? [[String]], !rawFrames.isEmpty else { continue }
            let fps = min(max((d["fps"] as? Int) ?? 8, 1), 30)
            var grids: [PixelGrid] = []
            for rows in rawFrames {
                guard rows.count == h else { continue }
                var g = PixelGrid(width: w, height: h)
                for (y, row) in rows.enumerated() {
                    for (x, ch) in row.prefix(w).enumerated() where ch != "." {
                        if let c = palette[ch] { g[x, y] = c }
                    }
                }
                grids.append(g)
            }
            guard !grids.isEmpty else { continue }
            out[key] = CharacterSprite(key: key, width: w, height: h, fps: fps, frames: grids)
        }
        return out
    }
}

extension RGBA {
    /// "#RRGGBB" or "RRGGBB".
    init?(hexString: String) {
        let s = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(hex: v)
    }
}
