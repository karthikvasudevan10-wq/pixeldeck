import SwiftUI

/// Community: everyone's shared sprites, newest first, as live looping tiles. "Mine" lists your
/// own posts so you can delete them.
struct CommunityView: View {
    @Environment(CommunityService.self) private var community
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
            content
        }
        .screenBackground()
        .task { if community.posts.isEmpty { await community.refresh() } }
        .sheet(item: $selected) { post in CommunityPostView(post: post) }
        .sheet(isPresented: $showingRules) { CommunityRulesView() }
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            tab("Newest", .newest)
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
                message(community.feed == .mine ? Text("You haven't shared anything yet.") : Text("Nothing here yet."),
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
                Text(post.isMine ? String(localized: "by you") : String(localized: "by \(post.author)", comment: "Community post credit; the placeholder is a nickname"))
                    .font(AppFont.body(12, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
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
    @State private var error: String?

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

                    Button(action: remix) {
                        PrimaryActionLabel(title: remixed ? "Added to your gallery" : "Remix", icon: remixed ? .check : .create, height: 50)
                    }
                    .buttonStyle(PrimaryButtonStyle(depth: 4))
                    .disabled(remixed)
                    .accessibilityHint("Copies this sprite into your gallery so you can edit it")

                    HStack(spacing: 8) {
                        if post.isMine || community.isModerator {
                            action(post.isMine ? "Delete my post" : "Remove (moderator)", tint: Theme.accent) { confirmingDelete = true }
                        }
                        if !post.isMine {
                            action("Report", tint: Theme.accent) { confirmingReport = true }
                            action("Block", tint: Theme.muted) { confirmingBlock = true }
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
        store.save(p)
        remixed = true
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
