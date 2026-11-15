import SwiftUI

/// In-app copy of the privacy policy (App Review 5.1.1 requires one to be reachable in the app).
/// Keep in sync with AppStore/privacy-policy.html.
struct PrivacyPolicyView: View {
    static let lastUpdated = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 11, day: 15).date ?? .now

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Last updated \(Self.lastUpdated, format: .dateTime.day().month(.wide).year())")
                    .font(AppFont.pixel(11))
                    .foregroundStyle(Theme.muted)

                section("The short version",
                        "Pixel Deck has no sign-up, no ads, no analytics and no tracking. Your sprites stay private unless you choose to share one to Community, which makes that sprite, its title and your nickname public.")
                section("Your artwork",
                        "Sprites you create are saved in the app's own storage. With iCloud sync on (the default, if you're signed in to iCloud), they're also kept in your own private iCloud account, so you can open them on your other devices signed in to it. That storage belongs to your Apple Account: only you can see it, and the developer has no access to it. Turn sync off in Settings to keep sprites on this device only. Reference images and tracing pictures are picked with the system photo picker, which gives the app only the image you choose; they're stored alongside your sprites in the same way. Pixel Deck has no servers of its own, and your art is only made public if you share it to Community.")
                section("Community",
                        "Community is optional. If you share a sprite to Community, its art, the title and the nickname you choose are published in Pixel Deck's public CloudKit database, hosted by Apple, where anyone using the app can see and copy them. CloudKit links each post to an anonymous identifier for your iCloud account (not your name or email), so you can delete your posts and others can block or report them. Reports you make are stored the same way. You can delete your posts at any time from Community, Mine. Posts that break the community rules are removed. The developer can see public posts and reports, and uses them only to run and moderate Community.")
                section("Exports and sharing",
                        "When you export, Pixel Deck creates image or video files on your device. If you choose Save to Photos, iOS asks whether Pixel Deck may add items to your photo library; it can only add, never read your photos. If you choose Share, the standard iOS share sheet opens, and where the files go next is your choice, handled by iOS or the app you pick.")
                section("Purchases",
                        "The optional Pixel Deck Pro upgrade is processed by Apple through the App Store. Pixel Deck receives only a confirmation that the purchase is valid; it never sees your payment details or Apple Account information.")
                section("Children",
                        "Pixel Deck doesn't collect personal information from anyone, including children. Community posts are public, so children should use a nickname that isn't their real name, and parents can turn off iCloud for the app in Screen Time to prevent posting.")
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
        .foregroundStyle(Theme.text)
        .tint(Theme.accent2)
        .screenBackground()
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func section(_ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(AppFont.body(16, .bold, relativeTo: .headline)).foregroundStyle(Theme.cream)
            Text(body).font(AppFont.body(15, relativeTo: .body)).foregroundStyle(Theme.text)
        }
    }
}
