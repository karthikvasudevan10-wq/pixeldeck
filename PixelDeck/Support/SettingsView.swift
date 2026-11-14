import SwiftUI

struct SettingsView: View {
    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    @State private var showingUpgrade = false
    @State private var showingTips = false

    var body: some View {
        NavigationStack {
            List {
                Section("Pixel Deck Pro") {
                    if purchases.isPro {
                        Label("Unlocked — thank you!", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button { showingUpgrade = true } label: {
                            Label("Unlock Pro", systemImage: "sparkles")
                        }
                    }
                    Button { Task { await purchases.restore() } } label: {
                        Label("Restore Purchases", systemImage: "arrow.clockwise")
                    }
                }

                Section("Help") {
                    Button { showingTips = true } label: {
                        Label("Show quick tips", systemImage: "lightbulb")
                    }
                    if let url = AppConfig.supportURL {
                        Link(destination: url) { Label("Support website", systemImage: "questionmark.circle") }
                    }
                    if let email = AppConfig.supportEmail, let url = URL(string: "mailto:\(email)") {
                        Link(destination: url) { Label("Contact support", systemImage: "envelope") }
                    }
                }

                Section("About") {
                    NavigationLink { PrivacyPolicyView() } label: {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    Link(destination: AppConfig.termsOfUseURL) {
                        Label("Terms of Use", systemImage: "doc.text")
                    }
                    LabeledContent("Version", value: AppConfig.version)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showingUpgrade) { ProUpgradeView() }
            .sheet(isPresented: $showingTips) { OnboardingView() }
            .alert("Pixel Deck Pro", isPresented: Binding(get: { purchases.errorMessage != nil && !showingUpgrade },
                                                          set: { if !$0 { purchases.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(purchases.errorMessage ?? "")
            }
        }
    }
}
