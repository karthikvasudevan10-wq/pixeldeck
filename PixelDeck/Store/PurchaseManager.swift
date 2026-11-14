import Foundation
import StoreKit
import Observation

/// One-time, non-consumable "Pixel Deck Pro" unlock via StoreKit 2.
/// The product must exist in App Store Connect with exactly `AppConfig.proProductID`.
@MainActor
@Observable
final class PurchaseManager {
    private(set) var product: Product?
    private(set) var isPro = false
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
            product = try await Product.products(for: [AppConfig.proProductID]).first
            loadFailed = product == nil
        } catch {
            loadFailed = true
        }
    }

    func refreshEntitlements() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == AppConfig.proProductID, t.revocationDate == nil {
                owned = true
            }
        }
        isPro = owned
    }

    func purchase() async {
        guard let product, !isPurchasing else { return }
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
                    errorMessage = "The App Store couldn't verify this purchase. Please try again."
                }
            case .pending:
                errorMessage = "Your purchase is waiting for approval. Pro unlocks as soon as it's approved."
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
            if !isPro { errorMessage = "No previous Pixel Deck Pro purchase was found for this Apple Account." }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
