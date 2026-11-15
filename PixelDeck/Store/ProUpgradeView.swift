import SwiftUI
import StoreKit

/// Paywall for the one-time Pro unlock. Always dismissible, shows the real localized price,
/// and offers Restore Purchases (App Review 3.1.1).
struct ProUpgradeView: View {
    /// The feature the user just tried to use, highlighted at the top.
    var highlight: ProFeature?
    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showingPrivacy = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Not now") { dismiss() }
                    .font(AppFont.body(15, .medium, relativeTo: .callout))
                    .foregroundStyle(Theme.accent2)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .center, spacing: 14) {
                        AnimatedSprite(key: "coin", pixel: 6)
                            .frame(width: 64, height: 64)
                            .background(Color(uiColor: Theme.dynamic(0x3A321C, 0xF4ECD6)))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pixel Deck Pro").font(AppFont.pixel(26)).foregroundStyle(Theme.cream)
                            Text("One purchase. No subscription.")
                                .font(AppFont.body(15, relativeTo: .subheadline))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    VStack(spacing: 8) {
                        ForEach(orderedFeatures) { row($0) }
                    }
                    Text("Free forever: every tool, mirror, onion skin, motion tweening, the infinite canvas up to 64 × 64 and PNG / sprite sheet export up to 4×.")
                        .font(AppFont.body(13, relativeTo: .footnote))
                        .foregroundStyle(Theme.muted)
                }
                .padding(16)
            }

            purchaseArea
        }
        .screenBackground()
        .onChange(of: purchases.isPro) { _, pro in if pro { dismiss() } }
        .sheet(isPresented: $showingPrivacy) {
            NavigationStack {
                PrivacyPolicyView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingPrivacy = false } } }
            }
        }
        .alert("Pixel Deck Pro", isPresented: Binding(get: { purchases.errorMessage != nil },
                                                      set: { if !$0 { purchases.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(purchases.errorMessage ?? "")
        }
    }

    private var orderedFeatures: [ProFeature] {
        guard let highlight else { return ProFeature.allCases }
        return [highlight] + ProFeature.allCases.filter { $0 != highlight }
    }

    private func row(_ f: ProFeature) -> some View {
        let on = f == highlight
        return HStack(alignment: .top, spacing: 14) {
            f.icon.view(size: 22)
                .foregroundStyle(on ? Theme.onAccent : Theme.accent)
                .frame(width: 40, height: 40)
                .background(on ? Theme.accent : Theme.tool)
            VStack(alignment: .leading, spacing: 2) {
                Text(f.title).font(AppFont.body(15, .bold, relativeTo: .headline)).foregroundStyle(Theme.cream)
                Text(f.detail).font(AppFont.body(13, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.surface)
        .overlay(Rectangle().strokeBorder(on ? Theme.accent : Theme.line, lineWidth: 2))
        .accessibilityElement(children: .combine)
    }

    private var purchaseArea: some View {
        VStack(spacing: 12) {
            if purchases.isPro {
                Text("Pro is unlocked. Thank you!").font(AppFont.pixel(14)).foregroundStyle(Theme.accent2)
            } else if let product = purchases.product {
                Button {
                    Task { await purchases.purchase() }
                } label: {
                    ZStack {
                        if purchases.isPurchasing {
                            ProgressView().tint(Theme.onAccent)
                        } else {
                            Text("Unlock for \(product.displayPrice)").font(AppFont.pixel(18))
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(purchases.isPurchasing)
                Text("One-time purchase of \(product.displayPrice). Family Sharing supported.")
                    .font(AppFont.body(12, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
            } else if purchases.loadFailed {
                VStack(spacing: 6) {
                    Text("The App Store isn't reachable right now.")
                        .font(AppFont.body(14, relativeTo: .subheadline))
                        .foregroundStyle(Theme.text)
                    Button("Try again") { Task { await purchases.loadProduct() } }
                        .foregroundStyle(Theme.accent2)
                }
            } else {
                ProgressView().tint(Theme.muted)
            }

            HStack(spacing: 18) {
                Button("Restore Purchases") { Task { await purchases.restore() } }
                Button("Terms of Use") { openURL(AppConfig.termsOfUseURL) }
                Button("Privacy") { showingPrivacy = true }
            }
            .font(AppFont.body(13, .medium, relativeTo: .footnote))
            .foregroundStyle(Theme.accent2)
        }
        .padding(16)
        .padding(.bottom, 4)
        .background(Theme.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Theme.line.frame(height: 2) }
    }
}

extension ProFeature {
    var icon: PixelIcon {
        switch self {
        case .largeCanvas: .select
        case .unlimitedFrames: .gallery
        case .gifExport: .play
        case .largeExport: .export
        }
    }
}

extension View {
    /// Presents the Pro paywall whenever `feature` is set.
    func proUpgradeSheet(_ feature: Binding<ProFeature?>) -> some View {
        sheet(item: feature) { f in
            ProUpgradeView(highlight: f)
        }
    }
}

/// Small "PRO" badge for locked options.
struct ProBadge: View {
    var body: some View {
        Text(verbatim: "PRO")
            .font(AppFont.pixel(9))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .foregroundStyle(Theme.onAccent2)
            .background(Theme.accent2)
            .accessibilityLabel("Requires Pro")
    }
}
