import SwiftUI
import UIKit
import WidgetKit
#if canImport(DeclaredAgeRange)
import DeclaredAgeRange
#endif

/// Community is a social feature, so it's off for under-13s. Before Community opens, iOS is asked
/// for the person's age range (Declared Age Range, iOS 26+: the person or their parent shares
/// it, never a birth date). The answer is cached and passed to the widget through the App Group.
@MainActor @Observable
final class AgeGate {
    enum Status: String {
        /// Not checked yet.
        case unknown
        case checking
        /// 13 or older, or a device too old for the age-range API (the App Store age rating and
        /// Screen Time cover those).
        case allowed
        case underThirteen
        /// The person chose not to share their age range.
        case declined
    }

    private(set) var status: Status

    static let appGroup = "group.karthikvasudevan.pixeldeck"
    /// Read by the widget: Community content may be shown.
    static let allowedKey = "communityAllowed"
    private static let statusKey = "ageGateStatus"
    private static let checkedKey = "ageGateCheckedAt"
    /// An "allowed" answer is asked again after this long; other answers every time Community opens.
    private static let recheckAfter: TimeInterval = 90 * 24 * 3600

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.statusKey).flatMap(Status.init(rawValue:)) ?? .unknown
        let checked = UserDefaults.standard.object(forKey: Self.checkedKey) as? Date ?? .distantPast
        status = saved == .allowed && Date().timeIntervalSince(checked) < Self.recheckAfter ? .allowed : .unknown
    }

    var isAllowed: Bool { status == .allowed }

    /// Asks iOS for the age range if needed. Safe to call every time Community opens.
    func check(force: Bool = false) async {
        guard force || status != .allowed, status != .checking else { return }
        status = .checking
        set(await Self.ask())
    }

    private func set(_ s: Status) {
        status = s
        UserDefaults.standard.set(s.rawValue, forKey: Self.statusKey)
        UserDefaults.standard.set(Date(), forKey: Self.checkedKey)
        UserDefaults(suiteName: Self.appGroup)?.set(s == .allowed, forKey: Self.allowedKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func ask() async -> Status {
        #if canImport(DeclaredAgeRange)
        if #available(iOS 26.0, *) {
            guard let presenter = topViewController() else { return .allowed }
            do {
                let response = try await AgeRangeService.shared.requestAgeRange(ageGates: 13, in: presenter)
                switch response {
                case .declinedSharing:
                    return .declined
                case .sharing(let range):
                    if let lower = range.lowerBound, lower >= 13 { return .allowed }
                    if let upper = range.upperBound, upper < 13 { return .underThirteen }
                    return range.lowerBound == nil ? .underThirteen : .allowed
                @unknown default:
                    return .declined
                }
            } catch {
                // The service isn't available here (e.g. not signed in): fall back to the App Store
                // age rating and Screen Time, as on older iOS.
                return .allowed
            }
        }
        #endif
        return .allowed
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        var top = (scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first)?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }
}

/// Shown instead of Community (and sharing) when the age check doesn't allow it.
struct AgeLockedView: View {
    let status: AgeGate.Status
    var onTryAgain: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            AnimatedSprite(key: "ghost", pixel: 5).accessibilityHidden(true)
            Group {
                if status == .underThirteen {
                    Text("Community is for ages 13 and up")
                } else {
                    Text("Community needs your age range")
                }
            }
            .font(AppFont.pixel(15))
            .foregroundStyle(Theme.cream)
            .multilineTextAlignment(.center)
            Group {
                if status == .underThirteen {
                    Text("To keep younger artists safe, sharing and browsing other people's art is switched off. Everything else is yours: draw, animate, remix the starters and export.")
                } else {
                    Text("To keep younger artists safe, Community opens once your age range is shared. Only an age range is shared, never your birthday.")
                }
            }
            .font(AppFont.body(14, relativeTo: .subheadline))
            .foregroundStyle(Theme.muted)
            .multilineTextAlignment(.center)
            if status == .declined {
                Button(action: onTryAgain) {
                    Text("Try again").font(AppFont.pixel(13)).padding(.horizontal, 18).frame(height: 44)
                }
                .buttonStyle(PrimaryButtonStyle(fill: Theme.accent2, shadow: Theme.accent2Shadow, depth: 3))
            }
        }
        .padding(32)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
