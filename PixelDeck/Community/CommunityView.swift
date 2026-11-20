import SwiftUI

/// Community: everyone's shared sprites, newest first, as live looping tiles. "Mine" lists your
/// own posts so you can delete them.
struct CommunityView: View {
    /// A post to open straight away (tapped in the Home Screen widget).
    var openPostID: String? = nil
    @Environment(CommunityService.self) private var community
    @Environment(AgeGate.self) private var ageGate
    @Environment(\.dismiss) private var dismiss
    @State private var selected: CommunityPost?
    @State private var showingRules = false

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Community", onClose: { dismiss() })
            HStack(spacing: 8) {
                tabs
                Spacer()
                Button { showingRules = true } label: {
                    Text("Rules").font(AppFont.pixel(11)).padding(.horizontal, 12).frame(height: 36)
                }
                .buttonStyle(TileButtonStyle(fill: Theme.surface, foreground: Theme.muted))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            .opacity(ageGate.isAllowed ? 1 : 0)
            if ageGate.isAllowed {
                content
            } else if ageGate.status == .checking || ageGate.status == .unknown {
                ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                AgeLockedView(status: ageGate.status) { Task { await ageGate.check(force: true) } }
            }
        }
        .screenBackground()
        .task {
            // Under-13s don't get Community: check the age range first.
            await ageGate.check()
            guard ageGate.isAllowed else { return }
            if let id = openPostID, let post = await community.fetchPost(id: id) { selected = post }
            if community.posts.isEmpty { await community.refresh() }
        }
        .sheet(item: $selected) { post in CommunityPostView(post: post) }
        .sheet(isPresented: $showingRules) { CommunityRulesView() }
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            tab("Newest", .newest)
            tab("Popular", .popular)
            tab("Mine", .mine)
        }
        .padding(3)
        .background(Theme.surface)
    }

    private func tab(_ title: LocalizedStringKey, _ f: CommunityService.Feed) -> some View {
        let on = community.feed == f
        return Button { Task { await community.show(f) } } label: {
            Text(title).font(AppFont.pixel(11)).padding(.horizontal, 12).frame(height: 36).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(on ? Theme.ink : Theme.muted)
        .background(on ? Theme.cream : .clear)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder
    private var content: some View {
        if !community.isConfigured {
            message(Text("Community isn't set up in this build."),
                    detail: Text("The developer needs to turn on CloudKit (see the submission checklist)."))
        } else if community.posts.isEmpty {
            switch community.phase {
            case .failed(let text):
                message(Text(verbatim: text), detail: nil, retry: true)
            case .loaded:
                message(community.feed == .mine ? Text("You haven't shared anything yet.")
                        : community.feed == .popular ? Text("No hearts yet. Open a post and tap the heart to cheer someone on!")
                        : Text("Nothing here yet."),
                        detail: Text("Share a sprite from its menu in the gallery or the studio."))
            default:
                ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 12)], spacing: 12) {
                    ForEach(community.posts) { post in
                        Button { selected = post } label: { CommunityTile(post: post) }
                            .buttonStyle(.plain)
                            .onAppear {
                                if post.id == community.posts.last?.id { Task { await community.loadMore() } }
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                if community.phase == .loading { ProgressView().tint(Theme.accent).padding() }
            }
            .refreshable { await community.refresh() }
        }
    }

    private func message(_ title: Text, detail: Text?, retry: Bool = false) -> some View {
        VStack(spacing: 12) {
            title.font(AppFont.pixel(14)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
            if let detail {
                detail.font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            }
            if retry {
                Button { Task { await community.refresh() } } label: {
                    Text("Try again").font(AppFont.pixel(11)).padding(.horizontal, 14).frame(height: 40)
                }
                .buttonStyle(TileButtonStyle())
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A post in the grid: its animation looping, title and nickname.
struct CommunityTile: View {
    let post: CommunityPost

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Theme.chip
                FrameLoop(frames: post.frames, durations: post.art.durations).padding(14)
            }
            .frame(height: 140)
            VStack(alignment: .leading, spacing: 2) {
                Text(post.title)
                    .font(AppFont.body(14, .bold, relativeTo: .subheadline))
                    .foregroundStyle(Theme.cream)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(post.isMine ? String(localized: "by you") : String(localized: "by \(post.author)", comment: "Community post credit; the placeholder is a nickname"))
                        .font(AppFont.body(12, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if post.hearts > 0 || post.heartedByMe {
                        HeartCount(count: post.hearts, filled: post.heartedByMe)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Theme.surface)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// One post: big preview, Remix into your gallery, and Report / Block / Delete.
struct CommunityPostView: View {
    let post: CommunityPost
    @Environment(CommunityService.self) private var community
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingReport = false
    @State private var confirmingBlock = false
    @State private var confirmingDelete = false
    @State private var remixed = false
    @State private var family: [CommunityPost] = []
    @State private var openRemix: CommunityPost?
    @State private var playingLevel: TileScene?
    @State private var error: String?
    @State private var heartError: String?
    /// The live copy from the service (hearts change while this is open).
    private var current: CommunityPost { community.posts.first { $0.id == post.id } ?? post }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Community", verbatim: post.title, onClose: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ZStack {
                        Theme.chip
                        FrameLoop(frames: post.frames, durations: post.art.durations).padding(20)
                    }
                    .frame(height: 300)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(post.isMine ? String(localized: "by you") : String(localized: "by \(post.author)", comment: "Community post credit; the placeholder is a nickname"))
                            .font(AppFont.body(15, .bold, relativeTo: .body)).foregroundStyle(Theme.cream)
                        Text("\(post.art.frames.count) frames · \(post.art.width)×\(post.art.height) · \(post.created.formatted(date: .abbreviated, time: .omitted))",
                             comment: "Community post details: frame count (plural), size and date")
                            .font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                    }

                    if !current.isMine {
                        Button {
                            Task { heartError = await community.toggleHeart(current) }
                        } label: {
                            HStack(spacing: 10) {
                                HeartShape(filled: current.heartedByMe).frame(width: 22, height: 20)
                                Text(current.heartedByMe ? "Hearted" : "Give a heart").font(AppFont.pixel(14))
                                Spacer()
                                Text(verbatim: "\(current.hearts)").font(AppFont.pixel(14)).monospacedDigit()
                            }
                            .foregroundStyle(current.heartedByMe ? Theme.onAccent : Theme.accent)
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                            .background(current.heartedByMe ? Theme.accent : Theme.surface)
                            .overlay(Rectangle().strokeBorder(Theme.accent, lineWidth: 2))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.impact(weight: .light), trigger: current.heartedByMe)
                        .accessibilityLabel(current.heartedByMe ? Text("Remove your heart") : Text("Give a heart"))
                        .accessibilityValue(Text("\(current.hearts) hearts"))
                        if let heartError {
                            Text(verbatim: heartError).font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.accent)
                        }
                    } else if current.hearts > 0 {
                        HStack(spacing: 8) {
                            HeartShape(filled: true).frame(width: 18, height: 16)
                            Text("\(current.hearts) hearts", comment: "Hearts on your own post (plural)")
                                .font(AppFont.body(14, .bold, relativeTo: .body)).foregroundStyle(Theme.cream)
                        }
                    }

                    if let remix = post.remix, !remix.title.isEmpty {
                        Text("A remix of \(remix.title) by \(remix.author)", comment: "Community post credit; placeholders are the original post's title and its author's nickname")
                            .font(AppFont.body(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.accent2)
                    }

                    if let level = post.level {
                        LevelPostActions(post: post, level: level, onPlay: { playingLevel = level })
                    } else {
                        Button(action: remix) {
                            PrimaryActionLabel(title: remixed ? "Added to your gallery" : "Remix", icon: remixed ? .check : .create, height: 50)
                        }
                        .buttonStyle(PrimaryButtonStyle(depth: 4))
                        .disabled(remixed)
                        .accessibilityHint("Copies this sprite into your gallery so you can edit it. Sharing your version credits this one.")
                    }

                    RemixFamilyRow(family: family, isMine: post.isMine, onOpen: { openRemix = $0 })

                    HStack(spacing: 8) {
                        if post.isMine || community.isModerator {
                            action(post.isMine ? "Delete my post" : "Remove (moderator)", tint: Theme.accent) { confirmingDelete = true }
                        }
                        if !post.isMine {
                            action("Report", tint: Theme.accent) { confirmingReport = true }
                            action("Block", tint: Theme.muted) { confirmingBlock = true }
                        } else if AppConfig.allowReportingOwnPosts {
                            // TEMPORARY, for recording the report flow (see AppConfig).
                            action("Report", tint: Theme.accent) { confirmingReport = true }
                        }
                    }
                    if let error {
                        Text(error).font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.accent)
                    }
                }
                .padding(16)
            }
        }
        .screenBackground()
        .presentationDetents([.large])
        .task { family = await community.remixes(of: post) }
        .sheet(item: $openRemix) { CommunityPostView(post: $0) }
        .fullScreenCover(item: $playingLevel) { PlaygroundPlayView(scene: $0) }
        .confirmationDialog("Report this post?", isPresented: $confirmingReport, titleVisibility: .visible) {
            ForEach(Self.reasons, id: \.self) { reason in
                Button(LocalizedStringKey(reason)) {
                    Task { await community.report(post, reason: reason); dismiss() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It's hidden for you straight away. Posts reported by several people are hidden for everyone and reviewed within 24 hours.")
        }
        .confirmationDialog("Block \(post.author)?", isPresented: $confirmingBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) { community.block(post); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won't see their posts any more. You can unblock everyone in Settings.")
        }
        .confirmationDialog("Delete this post?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    do { try await community.delete(post); dismiss() } catch { self.error = error.localizedDescription }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It's removed from Community for everyone. Copies people remixed into their own galleries stay theirs.")
        }
    }

    static let reasons = ["Offensive or inappropriate", "Spam", "Copied from someone else", "Something else"]

    private func action(_ title: LocalizedStringKey, tint: Color, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(title).font(AppFont.pixel(11)).frame(maxWidth: .infinity).frame(height: 44)
        }
        .buttonStyle(TileButtonStyle(foreground: tint))
    }

    private func remix() {
        var p = post.art.makeProject(name: String(localized: "\(post.title) remix", comment: "Name for a sprite copied from Community; the placeholder is the post's title"))
        p.modifiedAt = Date()
        // Remembered with the sprite, so sharing the remix credits this post.
        p.remix = RemixCredit(postID: post.id, title: post.title, author: post.author)
        store.save(p)
        remixed = true
    }
}

/// A post that is a Playground level: play it, or keep a copy to edit.
private struct LevelPostActions: View {
    let post: CommunityPost
    let level: TileScene
    var onPlay: () -> Void
    @State private var saved = false

    var body: some View {
        Button(action: onPlay) {
            PrimaryActionLabel(title: "Play this level", icon: .play, height: 50)
        }
        .buttonStyle(PrimaryButtonStyle(depth: 4))
        Button {
            var copy = level
            copy.id = UUID()
            copy.name = post.title
            copy.author = post.author
            SceneStore.forApp().save(copy)
            saved = true
        } label: {
            Text(saved ? "Added to your levels" : "Add to my levels").font(AppFont.pixel(13))
                .frame(maxWidth: .infinity, minHeight: 46).contentShape(Rectangle())
        }
        .buttonStyle(TileButtonStyle())
        .disabled(saved)
        .accessibilityHint("Copies this level into Playground so you can edit it")
    }
}

/// The posts remixed from this one.
private struct RemixFamilyRow: View {
    let family: [CommunityPost]
    let isMine: Bool
    var onOpen: (CommunityPost) -> Void

    var body: some View {
        if !family.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Remix family · \(family.count)", comment: "Heading above the posts remixed from this one")
                    .font(AppFont.pixel(12)).foregroundStyle(Theme.muted)
                if isMine {
                    Text("Your art inspired \(family.count) remixes.", comment: "Shown on your own post; plural")
                        .font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.accent2)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(family) { r in
                            Button { onOpen(r) } label: {
                                VStack(spacing: 4) {
                                    ZStack {
                                        Theme.chip
                                        if let first = r.frames.first { PixelImage(frame: first, checker: false).padding(6) }
                                    }
                                    .frame(width: 84, height: 84)
                                    Text(verbatim: r.title).font(AppFont.body(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.cream).lineLimit(1)
                                    Text("by \(r.author)", comment: "Community post credit; the placeholder is a nickname")
                                        .font(AppFont.body(11, relativeTo: .caption2)).foregroundStyle(Theme.muted).lineLimit(1)
                                }
                                .frame(width: 84)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

/// The community rules, shown before someone first posts and from the Community screen.
struct CommunityRulesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Community rules", onClose: { dismiss() })
            ScrollView {
                Text(Self.text)
                    .font(AppFont.body(15, relativeTo: .body))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
        .screenBackground()
    }

    static let text: LocalizedStringKey = """
    Community is a public space: anyone using Pixel Deck can see what you share.

    • Share only art you made or have the right to share.
    • Nothing hateful, violent, sexual, harassing or otherwise objectionable, in art, titles or nicknames. There is no tolerance for objectionable content or abusive users.
    • Don't share personal details: no real names, addresses, phone numbers or links.

    Anyone can report a post. A post reported by several people is hidden for everyone, and reports are reviewed within 24 hours; content that breaks these rules is removed, and people who break them are blocked from posting. You can block anyone so you don't see their posts, and you can delete your own posts at any time from Mine.

    Remix copies a post into your own gallery. Please credit the original artist if you share a remix.
    """
}

/// A pixel heart: filled when you've given one, outlined otherwise.
struct HeartShape: View {
    var filled: Bool

    private static let rows = [".##.##.", "#######", "#######", ".#####.", "..###..", "...#..."]
    private static let outline = [".##.##.", "#..#..#", "#.....#", ".#...#.", "..#.#..", "...#..."]

    var body: some View {
        Canvas { ctx, size in
            let grid = filled ? Self.rows : Self.outline
            let cw = size.width / 7, ch = size.height / 6
            for (y, row) in grid.enumerated() {
                for (x, c) in row.enumerated() where c == "#" {
                    ctx.fill(Path(CGRect(x: CGFloat(x) * cw, y: CGFloat(y) * ch, width: cw.rounded(.up), height: ch.rounded(.up))),
                             with: .foreground)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// "♥ 12" on a tile.
struct HeartCount: View {
    let count: Int
    var filled = false

    var body: some View {
        HStack(spacing: 4) {
            HeartShape(filled: true).frame(width: 11, height: 10)
            Text(verbatim: "\(count)").font(AppFont.pixel(10)).monospacedDigit()
        }
        .foregroundStyle(filled ? Theme.accent : Theme.muted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(count) hearts"))
    }
}
