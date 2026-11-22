import Foundation

// The platform-independent half of Community (sharing sprites publicly through CloudKit's public
// database): what a post carries, the text filter, and which posts are shown. The CloudKit calls
// are in the app layer (Community/CommunityService.swift).

/// The art in a community post: the visible layers flattened, trimmed to the art, plus its timing.
/// Stored as a JSON file (a CloudKit asset); pixel data is run-length encoded, so posts are small.
struct PostArt: Codable, Equatable, Sendable {
    var version = 1
    var width: Int
    var height: Int
    var fps: Int
    var easing: Easing
    var frames: [PixelGrid]

    static let maxFrames = 120
    static let maxSide = FeatureAccess.proMaxArtSide
    /// Posts larger than this (as JSON) are refused, to keep the feed quick.
    static let maxBytes = 3_000_000

    /// Nil for a blank sprite (nothing to share).
    init?(project: SpriteProject) {
        guard let r = project.visibleContentBounds, r.width <= Self.maxSide, r.height <= Self.maxSide else { return nil }
        width = r.width
        height = r.height
        // Community posts play at up to 30 frames a second (what every version of the app accepts).
        fps = min(project.fps, 30)
        easing = project.playbackEasing
        frames = Array(project.grids(croppedTo: r).prefix(Self.maxFrames))
    }

    var durations: [Double] { PlaybackTiming.durations(count: frames.count, fps: fps, easing: easing) }

    /// A new sprite for the user's gallery ("Remix").
    func makeProject(name: String) -> SpriteProject {
        var p = SpriteProject(name: name, bounds: PixelRect(x: -width / 2, y: -height / 2, width: width, height: height),
                              frames: frames, fps: fps)
        p.playbackEasing = easing
        return p
    }

    func encoded() throws -> Data { try JSONEncoder().encode(self) }

    /// Decodes and checks a downloaded post. Anything malformed or out of range is rejected, so a
    /// tampered post can't crash or exhaust the app.
    static func decode(_ data: Data) -> PostArt? {
        guard data.count <= maxBytes, let art = try? JSONDecoder().decode(PostArt.self, from: data) else { return nil }
        guard art.width > 0, art.height > 0, art.width <= maxSide, art.height <= maxSide,
              !art.frames.isEmpty, art.frames.count <= maxFrames, (1...30).contains(art.fps),
              art.frames.allSatisfy({ $0.width == art.width && $0.height == art.height }) else { return nil }
        return art
    }
}

/// Screens titles and nicknames before posting (and again when showing them, in case a post
/// didn't come from this app). Blocks profanity and slurs, including common letter swaps, and
/// links, email addresses and phone numbers (no spam, no sharing contact details).
enum ContentFilter {
    static let maxTitleLength = 40
    static let nicknameLength = 2...20

    /// Trims, collapses whitespace, removes control characters and limits the length.
    static func tidy(_ text: String, maxLength: Int) -> String {
        let cleaned = text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let words = String(String.UnicodeScalarView(cleaned)).split(whereSeparator: \.isWhitespace)
        return String(words.joined(separator: " ").prefix(maxLength))
    }

    static func isAcceptable(_ text: String) -> Bool {
        let lower = text.lowercased()
        // Links, emails and phone numbers.
        if lower.contains("http") || lower.contains("www.") || lower.range(of: #"[a-z0-9-]+\.(com|net|org|io|co|me|ly|gg|xyz|app|tv)\b"#, options: .regularExpression) != nil
            || lower.range(of: #"\S+@\S+\.\S+"#, options: .regularExpression) != nil
            || lower.filter(\.isNumber).count >= 7 {
            return false
        }
        let tokens = normalizedWords(text)
        if tokens.contains(where: { blockedWords.contains($0) || squeezedBlockedWords.contains(squeezed($0)) }) { return false }
        // Spelled out with spaces or symbols between letters ("f u c k", "f.u.c.k").
        let joined = tokens.joined()
        return !blockedStems.contains { joined.contains($0) || squeezed(joined).contains(squeezed($0)) }
    }

    /// Lower case, accents removed, common digit and symbol swaps undone, split into words.
    static func normalizedWords(_ text: String) -> [String] {
        let swaps: [Character: Character] = ["0": "o", "1": "i", "!": "i", "3": "e", "4": "a", "@": "a", "5": "s", "$": "s", "7": "t", "8": "b", "|": "l"]
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).lowercased()
        var out: [String] = []
        var word = ""
        for ch in folded {
            let c = swaps[ch] ?? ch
            if c.isLetter { word.append(c) } else if !word.isEmpty { out.append(word); word = "" }
        }
        if !word.isEmpty { out.append(word) }
        return out
    }

    /// "fuuuck" → "fuck", "shiiit" → "shit": repeated letters count once.
    static func squeezed(_ w: String) -> String {
        var r = ""
        for ch in w where r.last != ch { r.append(ch) }
        return r
    }

    /// Whole words only (so "classic" or "Scunthorpe" aren't caught).
    private static let blockedWords: Set<String> = [
        "fuck", "fucks", "fucker", "fuckers", "fucking", "fucked", "motherfucker", "shit", "shits", "shitty", "bullshit",
        "cunt", "cunts", "bitch", "bitches", "bastard", "dick", "dicks", "dickhead", "cock", "cocks", "pussy", "asshole",
        "arsehole", "twat", "wanker", "whore", "slut", "porn", "porno", "nude", "nudes", "sex", "sexy", "rape", "rapist",
        "nazi", "nazis", "hitler", "kys", "retard", "retarded", "fag", "fags", "faggot", "faggots", "nigger", "niggers",
        "nigga", "niggas", "chink", "chinks", "spic", "spics", "kike", "kikes", "tranny", "paki", "gook", "wetback",
    ]

    private static let squeezedBlockedWords = Set(blockedWords.map(squeezed))

    /// Distinctive enough to block even inside other text.
    private static let blockedStems = ["fuck", "nigger", "nigga", "faggot", "motherf", "killyourself"]
}

/// Which posts are shown. Posts reported by `hideAfterReports` different people are hidden for
/// everyone until the developer reviews them (CloudKit Console). Posts the user reported, and
/// posts by people they blocked, are hidden for them straight away.
enum CommunityModeration {
    static let hideAfterReports = 3

    static func isVisible(postID: String, authorID: String?, title: String, author: String,
                          reporters: Set<String>, blockedAuthors: Set<String>, reportedByMe: Set<String>) -> Bool {
        if reportedByMe.contains(postID) { return false }
        if let authorID, blockedAuthors.contains(authorID) { return false }
        if reporters.count >= hideAfterReports { return false }
        return ContentFilter.isAcceptable(title) && ContentFilter.isAcceptable(author)
    }
}
