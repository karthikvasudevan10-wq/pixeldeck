import Foundation

/// Values to fill in before submitting to the App Store. See AppStore/SUBMISSION_CHECKLIST.md.
enum AppConfig {
    /// Must match the non-consumable in-app purchase created in App Store Connect,
    /// and the product in PixelDeck.storekit (used for testing in Xcode).
    static let proProductID = "com.example.pixeldeck.pro"

    /// Public web address of your privacy policy (a hosted copy of AppStore/privacy-policy.html).
    /// Leave nil to show only the in-app copy. App Store Connect still needs the URL.
    static let privacyPolicyURL: URL? = nil

    /// Support page or contact form. App Store Connect requires a support URL.
    static let supportURL: URL? = nil

    /// Shown in Settings as "Contact support" if set.
    static let supportEmail: String? = nil

    /// Apple's standard licence agreement, used unless you provide your own EULA.
    static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    static var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
