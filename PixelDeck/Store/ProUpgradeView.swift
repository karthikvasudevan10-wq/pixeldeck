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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    VStack(spacing: 14) {
                        ForEach(orderedFeatures) { feature in
                            row(feature)
                        }
                    }
                    .padding(.horizontal)

                    Text("Free forever: every drawing tool, onion skin, motion tweening, and PNG / sprite sheet export up to 4×.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.vertical, 24)
            }
            .safeAreaInset(edge: .bottom) { purchaseArea }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
            .onChange(of: purchases.isPro) { _, pro in
                if pro { dismiss() }
            }
            .alert("Pixel Deck Pro", isPresented: Binding(get: { purchases.errorMessage != nil },
                                                          set: { if !$0 { purchases.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(purchases.errorMessage ?? "")
            }
        }
    }

    private var orderedFeatures: [ProFeature] {
        guard let highlight else { return ProFeature.allCases }
        return [highlight] + ProFeature.allCases.filter { $0 != highlight }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("Pixel Deck Pro")
                .font(.largeTitle.bold())
            Text("One purchase. No subscription. Yours on all your devices.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }

    private func row(_ feature: ProFeature) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: feature.symbol)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title).font(.headline)
                Text(feature.detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(feature == highlight ? Color.accentColor.opacity(0.12) : Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var purchaseArea: some View {
        VStack(spacing: 10) {
            if purchases.isPro {
                Label("Pro is unlocked. Thank you!", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
            } else if let product = purchases.product {
                Button {
                    Task { await purchases.purchase() }
                } label: {
                    Group {
                        if purchases.isPurchasing {
                            ProgressView()
                        } else {
                            Text("Unlock for \(product.displayPrice)")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.borderedProminent)
                .disabled(purchases.isPurchasing)
                Text("One-time purchase of \(product.displayPrice). Family Sharing supported.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if purchases.loadFailed {
                VStack(spacing: 6) {
                    Text("The App Store isn't reachable right now.")
                        .font(.subheadline)
                    Button("Try again") { Task { await purchases.loadProduct() } }
                }
            } else {
                ProgressView()
            }

            HStack(spacing: 18) {
                Button("Restore Purchases") { Task { await purchases.restore() } }
                Button("Terms of Use") { openURL(AppConfig.termsOfUseURL) }
                NavigationLink("Privacy") { PrivacyPolicyView() }
            }
            .font(.footnote)
        }
        .padding()
        .background(.bar)
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
        Text("PRO")
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .foregroundStyle(.white)
            .background(Color.accentColor, in: Capsule())
            .accessibilityLabel("Requires Pro")
    }
}
