import Foundation

/// Values to fill in before submitting to the App Store. See AppStore/SUBMISSION_CHECKLIST.md.
enum AppConfig {
    /// Must match the non-consumable in-app purchase created in App Store Connect,
    /// and the product in PixelDeck.storekit (used for testing in Xcode).
    static let proProductID = "karthikvasudevan.pixeldeck.pro"

    /// The website (Website/), published to GitHub Pages by .github/workflows/pixeldeck-pages.yml.
    static let websiteURL = URL(string: "https://karthikvasudevan10-wq.github.io/pixeldeck/")!

    /// Public web address of the privacy policy (Website/privacy.html). Also entered in App Store Connect.
    static let privacyPolicyURL: URL? = URL(string: "privacy.html", relativeTo: websiteURL)?.absoluteURL

    /// Support page (Website/support.html). App Store Connect requires a support URL.
    static let supportURL: URL? = URL(string: "support.html", relativeTo: websiteURL)?.absoluteURL

    /// Shown in Settings as "Contact support", and the contact for Community reports.
    static let supportEmail: String? = "karthik.vasudevan.10@gmail.com"

    /// The CloudKit container for Community (public sharing), e.g. "iCloud.com.yourname.pixeldeck".
    /// Must be ticked under the iCloud capability's CloudKit service. Nil turns Community off
    /// (CloudKit crashes an app that uses a container it isn't entitled to).
    static let cloudKitContainerID: String? = "iCloud.karthikvasudevan.pixeldeck"

    /// TEMPORARY: shows Report on your own Community posts, so the report flow can be screen
    /// recorded for App Review without a second account. Set back to `false` (and rebuild)
    /// before the build you submit.
    static let allowReportingOwnPosts = true

    /// CloudKit user ids allowed to remove anyone's post in the app (give that account the
    /// Moderator security role in CloudKit Console). Find yours in Settings › Community.
    static let communityModeratorIDs: Set<String> = []

    /// Apple's standard licence agreement, used unless you provide your own EULA.
    static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    static var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
