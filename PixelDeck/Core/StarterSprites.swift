import Foundation

/// Animations described as character grids (the design handoff's `sprites.json`):
///
///     { "pal": { "k": "#1B1530", … },
///       "slime": { "w": 12, "h": 16, "fps": 8, "frames": [ ["....kkkk....", …], … ] }, … }
///
/// `.` is transparent; any other character is a key into `pal`. A sprite can carry its own `pal`,
/// which adds to (and overrides) the shared one, for art with many colours. Used for the starter sprites in
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

    /// A new sprite with these frames, centred on world (0, 0). Its id comes from `key`, so the
    /// same starter added on two devices syncs as one sprite rather than two.
    func makeProject(name: String) -> SpriteProject {
        let bounds = PixelRect(x: -width / 2, y: -height / 2, width: width, height: height)
        var p = SpriteProject(name: name, bounds: bounds, frames: frames, fps: fps)
        p.id = UUID(stableName: "pixeldeck.starter.\(key)")
        return p
    }
}

enum CharacterSpriteLibrary {
    /// Order the starter sprites appear in.
    static let order = ["slime", "flame", "coin", "ghost", "sprout", "moon"]
    /// The large animated scenes (bigger than the free art size, so editing them needs Pro).
    static let showcaseOrder = ["highstreet", "valley"]

    /// Parses the JSON. Malformed sprites are skipped rather than failing the whole file.
    static func parse(_ data: Data) -> [String: CharacterSprite] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        func readPalette(_ any: Any?, into palette: inout [Character: RGBA]) {
            for (k, v) in (any as? [String: String]) ?? [:] {
                if let ch = k.first, k.count == 1, let c = RGBA(hexString: v) { palette[ch] = c }
            }
        }
        var shared: [Character: RGBA] = [:]
        readPalette(root["pal"], into: &shared)
        var out: [String: CharacterSprite] = [:]
        for (key, value) in root where key != "pal" {
            guard let d = value as? [String: Any],
                  let w = d["w"] as? Int, let h = d["h"] as? Int, w > 0, h > 0, w <= 256, h <= 256,
                  let rawFrames = d["frames"] as? [[String]], !rawFrames.isEmpty else { continue }
            let fps = min(max((d["fps"] as? Int) ?? 8, 1), 30)
            var palette = shared
            readPalette(d["pal"], into: &palette)
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

extension UUID {
    /// The same UUID for the same name, on every device (two FNV-1a hashes, version 8 layout).
    init(stableName: String) {
        func fnv(_ seed: UInt64) -> UInt64 {
            var h: UInt64 = 0xcbf29ce484222325 ^ seed
            for b in stableName.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
            return h
        }
        let a = fnv(0), b = fnv(0x9E3779B97F4A7C15)
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 { bytes[i] = UInt8(truncatingIfNeeded: a >> (8 * UInt64(i))); bytes[8 + i] = UInt8(truncatingIfNeeded: b >> (8 * UInt64(i))) }
        bytes[6] = (bytes[6] & 0x0F) | 0x80        // version 8 (custom)
        bytes[8] = (bytes[8] & 0x3F) | 0x80        // RFC 4122 variant
        self.init(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                         bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
