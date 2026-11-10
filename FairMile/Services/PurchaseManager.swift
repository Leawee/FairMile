import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class PurchaseManager {
    private(set) var products: [Product] = []
    private(set) var isPlus = false
    private(set) var loadError: String?
    private var updates: Task<Void, Never>?

    func start() async {
        await refreshEntitlements()
        await loadProducts()
        updates?.cancel()
        updates = Task { await listen() }
    }

    func loadProducts() async {
        do {
            let ids = PlusProduct.allCases.map(\.rawValue)
            products = try await Product.products(for: ids).sorted { rank($0) < rank($1) }
            loadError = products.isEmpty ? "App Store prices are not available in this build yet." : nil
        } catch {
            loadError = "The App Store products could not be loaded."
        }
    }

    func purchase(_ product: Product) async -> Bool {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard let transaction = verified(verification) else { return false }
                await transaction.finish()
                await refreshEntitlements()
                return isPlus
            case .pending, .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            loadError = "The purchase did not go through."
            return false
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !isPlus {
                loadError = "No active FairMile Plus purchase was found for this Apple ID."
            } else {
                loadError = nil
            }
        } catch {
            loadError = "Purchases could not be restored."
        }
    }

    func yearlyProduct() -> Product? {
        products.first { $0.id == PlusProduct.yearly.rawValue }
    }

    var orderedProducts: [Product] {
        products.sorted { rank($0) < rank($1) }
    }

    func trialText(for product: Product) -> String? {
        guard let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        if offer.period.unit == .day, offer.period.value == 7 {
            return "7-day free trial"
        }
        return "Free trial included"
    }

    private func listen() async {
        for await update in Transaction.updates {
            guard let transaction = verified(update) else { continue }
            await transaction.finish()
            await refreshEntitlements()
        }
    }

    private func refreshEntitlements() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = verified(result) else { continue }
            guard PlusProduct(rawValue: transaction.productID) != nil else { continue }
            if let expiration = transaction.expirationDate, expiration < Date() { continue }
            entitled = true
        }
        isPlus = entitled
    }

    private func verified<T>(_ result: VerificationResult<T>) -> T? {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            return nil
        }
    }

    private func rank(_ product: Product) -> Int {
        switch product.id {
        case PlusProduct.yearly.rawValue: 0
        case PlusProduct.lifetime.rawValue: 1
        default: 2
        }
    }
}
