import SwiftUI

/// Shares a sprite to Community: a title, your nickname, and (the first time) agreeing to the rules.
struct ShareToCommunityView: View {
    let project: SpriteProject
    /// Set when sharing a Playground level (`project` is then its picture).
    var level: TileScene? = nil
    @Environment(CommunityService.self) private var community
    @Environment(AgeGate.self) private var ageGate
    @Environment(\.dismiss) private var dismiss
    @AppStorage("communityNickname") private var nickname = ""
    @AppStorage("communityRulesAccepted") private var rulesAccepted = false
    @State private var title = ""
    @State private var agreed = false
    @State private var posting = false
    @State private var posted = false
    @State private var error: String?
    @State private var showingRules = false

    private var art: PostArt? { PostArt(project: project) }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Share to Community", onClose: { dismiss() })
            if !ageGate.isAllowed {
                if ageGate.status == .checking || ageGate.status == .unknown {
                    ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    AgeLockedView(status: ageGate.status) { Task { await ageGate.check(force: true) } }
                }
            } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let art {
                        ZStack {
                            Theme.chip
                            FrameLoop(frames: art.frames.map { Frame(grid: $0) }, durations: art.durations).padding(16)
                        }
                        .frame(height: 200)
                    }

                    field("Title", text: $title, limit: ContentFilter.maxTitleLength)
                    field("Your nickname", text: $nickname, limit: ContentFilter.nicknameLength.upperBound)
                    Text("Shown with your post. Don't use your real name.")
                        .font(AppFont.body(12, relativeTo: .caption)).foregroundStyle(Theme.muted)

                    if !rulesAccepted {
                        Toggle(isOn: $agreed) {
                            Text("I agree to the community rules. Objectionable content isn't allowed, and posts that break the rules are removed.")
                                .font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.text)
                        }
                        .tint(Theme.accent)
                        Button("Read the rules") { showingRules = true }
                            .font(AppFont.body(13, .medium, relativeTo: .footnote))
                            .foregroundStyle(Theme.accent2)
                    }

                    if let remix = project.remix, !remix.title.isEmpty {
                        Text("Shared as a remix of \(remix.title) by \(remix.author), with credit.", comment: "Sharing a remix; placeholders are the original post's title and its author's nickname")
                            .font(AppFont.body(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.accent2)
                    }
                    Text("Everyone using Pixel Deck can see, and remix, what you share. You can delete it later from Community › Mine.")
                        .font(AppFont.body(12, relativeTo: .caption)).foregroundStyle(Theme.muted)

                    if let error {
                        Text(error).font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.accent)
                    }

                    Button(action: post) {
                        HStack(spacing: 10) {
                            if posting { ProgressView().tint(Theme.onAccent) }
                            PrimaryActionLabel(title: posted ? "Shared!" : "Share", icon: posted ? .check : .share, height: 52)
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(depth: 4))
                    .disabled(!canPost)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            }
        }
        .screenBackground()
        .task { await ageGate.check() }
        .presentationDetents([.large])
        .onAppear { if title.isEmpty { title = project.name } }
        .sheet(isPresented: $showingRules) { CommunityRulesView() }
    }

    private var canPost: Bool {
        !posting && !posted && art != nil && (rulesAccepted || agreed)
            && !title.trimmingCharacters(in: .whitespaces).isEmpty
            && ContentFilter.nicknameLength.contains(nickname.trimmingCharacters(in: .whitespaces).count)
    }

    private func field(_ label: LocalizedStringKey, text: Binding<String>, limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(AppFont.pixel(11)).foregroundStyle(Theme.muted)
            TextField(label, text: text)
                .font(AppFont.body(16, relativeTo: .body))
                .foregroundStyle(Theme.text)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .frame(height: 46)
                .background(Theme.surface)
                .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
                .onChange(of: text.wrappedValue) { _, v in if v.count > limit { text.wrappedValue = String(v.prefix(limit)) } }
        }
    }

    private func post() {
        error = nil
        posting = true
        Task {
            do {
                try await community.publish(project, title: title, nickname: nickname, level: level)
                rulesAccepted = true
                posted = true
                try? await Task.sleep(for: .seconds(1))
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            posting = false
        }
    }
}
