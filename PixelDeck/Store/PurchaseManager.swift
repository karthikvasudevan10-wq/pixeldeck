import Foundation
import StoreKit
import Observation

/// One-time, non-consumable "Pixel Deck Pro" unlock via StoreKit 2.
/// The product must exist in App Store Connect with exactly `AppConfig.proProductID`.
@MainActor
@Observable
final class PurchaseManager {
    private(set) var product: Product?
    /// Pro is unlocked: bought, or inside the free trial.
    private(set) var isPro = false
    /// Bought (not just trying).
    private(set) var ownsPro = false
    /// The free trial, if it's set up in App Store Connect.
    private(set) var trialProduct: Product?
    /// When the trial ends (or ended); nil if it was never started.
    private(set) var trialEnds: Date?
    @ObservationIgnored private var trialTimer: Task<Void, Never>?

    var trialActive: Bool { !ownsPro && (trialEnds ?? .distantPast) > Date() }
    /// The trial can be started: it exists, and hasn't been used.
    var canStartTrial: Bool { !ownsPro && trialProduct != nil && trialEnds == nil }
    /// Whole days left in the trial (at least 1 while it's running).
    var trialDaysLeft: Int {
        guard let end = trialEnds, trialActive else { return 0 }
        return max(1, Int((end.timeIntervalSinceNow / 86_400).rounded(.up)))
    }
    /// False until the first check of existing purchases finishes (moments after launch).
    private(set) var entitlementsLoaded = false
    private(set) var isPurchasing = false
    private(set) var loadFailed = false
    var errorMessage: String?

    var access: FeatureAccess { isPro ? .pro : .free }

    @ObservationIgnored private var updates: Task<Void, Never>?

    init() {
        // Purchases made on another device, Ask to Buy approvals, refunds and Family Sharing changes.
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }
        Task {
            await refreshEntitlements()
            await loadProduct()
        }
    }

    func loadProduct() async {
        loadFailed = false
        do {
            let products = try await Product.products(for: [AppConfig.proProductID, AppConfig.trialProductID])
            product = products.first { $0.id == AppConfig.proProductID }
            trialProduct = products.first { $0.id == AppConfig.trialProductID }
            loadFailed = product == nil
        } catch {
            loadFailed = true
        }
    }

    func refreshEntitlements() async {
        var owned = false
        var trialStart: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil else { continue }
            if t.productID == AppConfig.proProductID { owned = true }
            if t.productID == AppConfig.trialProductID { trialStart = t.originalPurchaseDate }
        }
        ownsPro = owned
        trialEnds = trialStart.map { $0.addingTimeInterval(Double(AppConfig.trialDays) * 86_400) }
        isPro = owned || trialActive
        entitlementsLoaded = true
        // The trial ends by itself: check again at that moment.
        trialTimer?.cancel()
        if let end = trialEnds, trialActive {
            trialTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(1, end.timeIntervalSinceNow + 1)))
                if !Task.isCancelled { await self?.refreshEntitlements() }
            }
        }
    }

    /// Starts the free trial. Nothing is charged, and it ends by itself.
    func startTrial() async {
        guard let trialProduct, canStartTrial else { return }
        await buy(trialProduct)
    }

    func purchase() async {
        guard let product else { return }
        await buy(product)
    }

    private func buy(_ product: Product) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await refreshEntitlements()
                case .unverified:
                    errorMessage = String(localized: "The App Store couldn't verify this purchase. Please try again.")
                }
            case .pending:
                errorMessage = String(localized: "Your purchase is waiting for approval. Pro unlocks as soon as it's approved.", comment: "Shown for Ask to Buy / pending purchases")
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Required by App Review guideline 3.1.1 for restorable purchases.
    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !ownsPro { errorMessage = String(localized: "No previous Pixel Deck Pro purchase was found for this Apple Account.") }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
