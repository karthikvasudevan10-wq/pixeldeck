import SwiftUI

/// In-app copy of the privacy policy (App Review 5.1.1 requires one to be reachable in the app).
/// Keep in sync with AppStore/privacy-policy.html.
struct PrivacyPolicyView: View {
    static let lastUpdated = "13 November 2026"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Last updated \(Self.lastUpdated)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                section("The short version",
                        "Pixel Deck does not collect, store or share any personal information. There are no accounts, no ads, no analytics and no tracking.")
                section("Your artwork",
                        "Sprites you create are saved only on your device, inside the app's own storage. They're included in your device backups (iCloud or computer) the same way as other app data, under your control. Pixel Deck never uploads them.")
                section("Exports and sharing",
                        "When you export, Pixel Deck creates image files and opens the standard iOS share sheet. Where those files go next — Photos, Files, Messages, another app — is your choice, and is handled by iOS or that app, not by Pixel Deck.")
                section("Purchases",
                        "The optional Pixel Deck Pro upgrade is processed by Apple through the App Store. Pixel Deck receives only a confirmation that the purchase is valid; it never sees your payment details or Apple Account information.")
                section("Children",
                        "Pixel Deck collects no data from anyone, including children.")
                section("Changes",
                        "If this policy ever changes, the updated version will be published here and on the App Store listing, with a new date above.")
                if let url = AppConfig.privacyPolicyURL {
                    Link("View this policy on the web", destination: url)
                }
                if let email = AppConfig.supportEmail, let url = URL(string: "mailto:\(email)") {
                    Link("Questions? Contact \(email)", destination: url)
                }
            }
            .padding()
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(body)
        }
    }
}
