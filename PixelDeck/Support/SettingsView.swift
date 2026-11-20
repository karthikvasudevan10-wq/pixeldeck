import SwiftUI

struct SettingsView: View {
    @Environment(PurchaseManager.self) private var purchases
    @Environment(CloudSync.self) private var cloud
    @Environment(CommunityService.self) private var community
    /// Replays the guided tour (the gallery starts it once Settings has closed).
    var onStartTour: (() -> Void)? = nil
    @State private var showingRules = false
    @State private var communityID: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showingUpgrade = false
    @State private var showingSwipes = false
    @AppStorage("pencilOnly") private var pencilOnly = false

    private var cloudStatus: LocalizedStringKey {
        switch cloud.status {
        case .off: "Your sprites are kept on this device only. Turn on to keep them in your iCloud and open them on your other devices."
        case .checking: "Checking iCloud…"
        case .unavailable: "iCloud isn't available. Sign in to your Apple Account and turn on iCloud Drive in the Settings app. Your sprites are kept on this device until then."
        case .syncing: "Syncing your sprites with iCloud…"
        case .upToDate: "Your sprites are in your iCloud and on every device signed in to it. Only you can see them."
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SheetHeader(title: "Settings", onClose: { dismiss() })
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        group("Pixel Deck Pro") {
                            if purchases.isPro {
                                row(icon: .check, title: "Pro is unlocked. Thank you!", tint: Theme.accent2) {}
                                    .disabled(true)
                            } else {
                                row(icon: .plus, title: "Unlock Pro", tint: Theme.accent) { showingUpgrade = true }
                            }
                            row(icon: .undo, title: "Restore purchases") { Task { await purchases.restore() } }
                        }

                        group("Drawing") {
                            Toggle(isOn: $pencilOnly) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Draw with Apple Pencil only")
                                        .font(AppFont.body(15, .medium, relativeTo: .body))
                                        .foregroundStyle(Theme.text)
                                    Text("Fingers move and zoom the canvas, and a resting palm can't draw. Turns on by itself the first time you use a Pencil.")
                                        .font(AppFont.body(12, relativeTo: .caption))
                                        .foregroundStyle(Theme.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .tint(Theme.accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Theme.surface)
                        }

                        group("iCloud") {
                            Toggle(isOn: Binding(get: { cloud.enabled }, set: { cloud.enabled = $0 })) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Sync with iCloud")
                                        .font(AppFont.body(15, .medium, relativeTo: .body))
                                        .foregroundStyle(Theme.text)
                                    Text(cloudStatus)
                                        .font(AppFont.body(12, relativeTo: .caption))
                                        .foregroundStyle(Theme.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .tint(Theme.accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Theme.surface)
                        }

                        if community.isConfigured {
                            group("Community") {
                                row(icon: .community, title: "Community rules") { showingRules = true }
                                row(icon: .eyeOff, title: community.blockedAuthors.isEmpty
                                    ? LocalizedStringKey("No one blocked")
                                    : LocalizedStringKey("Unblock everyone (\(community.blockedAuthors.count))")) {
                                    community.unblockAll()
                                }
                                .disabled(community.blockedAuthors.isEmpty)
                                // For the developer setting up moderation (AppConfig.communityModeratorIDs).
                                row(icon: .more, title: communityID.map { LocalizedStringKey("ID: \($0)") } ?? LocalizedStringKey("Show my Community ID")) {
                                    Task {
                                        communityID = await community.myCommunityID()
                                        if let id = communityID { UIPasteboard.general.string = id }
                                    }
                                }
                            }
                        }

                        // AI assistants draw through a local server, which only the Mac app runs.
                        if ProcessInfo.processInfo.isMacCatalystApp {
                            group("AI assistants") { AISettingsSection() }
                        }

                        group("Help") {
                            if let onStartTour {
                                row(icon: .play, title: "Take the guided tour", tint: Theme.accent2, action: onStartTour)
                            }
                            row(icon: .arrowLeft, title: "How the swipes work") { showingSwipes = true }
                            if let url = AppConfig.supportURL {
                                row(icon: .share, title: "Support website") { openURL(url) }
                            }
                            if let email = AppConfig.supportEmail, let url = URL(string: "mailto:\(email)") {
                                row(icon: .share, title: "Contact support") { openURL(url) }
                            }
                        }

                        group("About") {
                            NavigationLink { PrivacyPolicyView() } label: { rowLabel(icon: .more, title: "Privacy policy") }
                                .buttonStyle(.plain)
                            row(icon: .export, title: "Terms of use") { openURL(AppConfig.termsOfUseURL) }
                            NavigationLink { LicensesView() } label: { rowLabel(icon: .more, title: "Font licences") }
                                .buttonStyle(.plain)
                            HStack {
                                Text("Version").font(AppFont.body(15, relativeTo: .body)).foregroundStyle(Theme.text)
                                Spacer()
                                Text(verbatim: AppConfig.version).font(AppFont.pixel(12)).foregroundStyle(Theme.muted)
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 52)
                            .background(Theme.surface)
                        }
                    }
                    .padding(16)
                }
            }
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showingUpgrade) { ProUpgradeView() }
        .sheet(isPresented: $showingRules) { CommunityRulesView() }
        .fullScreenCover(isPresented: $showingSwipes) { WelcomeFlow(startOnGestures: true) { showingSwipes = false } }
        .alert("Pixel Deck Pro", isPresented: Binding(get: { purchases.errorMessage != nil && !showingUpgrade },
                                                      set: { if !$0 { purchases.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(purchases.errorMessage ?? "")
        }
    }

    private func group<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: title)
            content()
        }
    }

    private func row(icon: PixelIcon, title: LocalizedStringKey, tint: Color = Theme.muted, action: @escaping () -> Void) -> some View {
        Button(action: action) { rowLabel(icon: icon, title: title, tint: tint) }
            .buttonStyle(.plain)
    }

    private func rowLabel(icon: PixelIcon, title: LocalizedStringKey, tint: Color = Theme.muted) -> some View {
        HStack(spacing: 12) {
            icon.view(size: 18).foregroundStyle(tint)
            Text(title).font(AppFont.body(15, .medium, relativeTo: .body)).foregroundStyle(Theme.text)
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .background(Theme.surface)
        .contentShape(Rectangle())
    }
}

/// The SIL Open Font License requires the licence to ship with the fonts.
private struct LicensesView: View {
    private var text: String {
        guard let url = Bundle.main.url(forResource: "FONT-LICENSES", withExtension: "txt"),
              let s = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return s
    }

    var body: some View {
        ScrollView {
            Text(verbatim: text)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Theme.text)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .screenBackground()
        .navigationTitle("Font licences")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}
