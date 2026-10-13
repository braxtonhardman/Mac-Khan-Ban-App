import Foundation
import Combine
import StoreKit

/// Purchasing is separate from the iCloud profile: ownership comes from verified App Store transactions.
enum UnlimitedProduct {
    static let id = "com.braxtonhardman.Tierin.unlimited.monthly"
    static let liveCheckoutEnabled = true
}

enum UnlimitedPurchaseOutcome { case completed, pending, cancelled }

@MainActor
protocol UnlimitedPurchasing {
    func displayPrice() async throws -> String?
    func hasEntitlement() async -> Bool
    func purchase() async throws -> UnlimitedPurchaseOutcome
    func restore() async throws
    func updates() -> AsyncStream<Void>
}

@MainActor
final class StoreKitUnlimitedPurchasing: UnlimitedPurchasing {
    private var product: Product?

    func displayPrice() async throws -> String? {
        product = try await Product.products(for: [UnlimitedProduct.id])
            .first { $0.id == UnlimitedProduct.id && $0.type == .autoRenewable
                && $0.subscription?.subscriptionPeriod.value == 1
                && $0.subscription?.subscriptionPeriod.unit == .month }
        return product?.displayPrice
    }

    private static func grantsAccess(_ transaction: StoreKit.Transaction) -> Bool {
        transaction.productID == UnlimitedProduct.id
            && transaction.productType == .autoRenewable
            && transaction.revocationDate == nil
            && !transaction.isUpgraded

    }

    func hasEntitlement() async -> Bool {
        // StoreKit includes active subscriptions and billing grace periods, but not expired access.
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result, Self.grantsAccess(transaction) {
                return true
            }
        }
        return false
    }

    func purchase() async throws -> UnlimitedPurchaseOutcome {
        guard let product else { throw PurchaseError.unavailable }
        switch try await product.purchase() {
        case .success(let result):
            guard case .verified(let transaction) = result, Self.grantsAccess(transaction) else {
                throw PurchaseError.unverified
            }
            await transaction.finish()
            return .completed
        case .pending: return .pending
        case .userCancelled: return .cancelled
        @unknown default: throw PurchaseError.unavailable
        }
    }

    func restore() async throws { try await AppStore.sync() }

    func updates() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                for await result in StoreKit.Transaction.updates {
                    guard !Task.isCancelled else { break }
                    // Re-read currentEntitlements even for refunds or an unverifiable update.
                    continuation.yield(())
                    if case .verified(let transaction) = result,
                       transaction.productID == UnlimitedProduct.id {
                        await transaction.finish()
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private enum PurchaseError: LocalizedError {
    case unavailable, unverified
    var errorDescription: String? {
        switch self {
        case .unavailable: "Purchases are unavailable right now. Please try again later."
        case .unverified: "The App Store couldn’t verify this purchase. Try Restore Purchases."
        }
    }
}

@MainActor
final class PurchaseStore: ObservableObject {
    @Published private(set) var hasUnlimited = false
    @Published private(set) var hasCheckedEntitlements = false
    @Published private(set) var isBusy = false
    @Published private(set) var isLoadingOffer = false
    @Published private(set) var price: String?
    @Published private(set) var message: String?
    let checkoutEnabled: Bool
    private let client: any UnlimitedPurchasing
    private var listener: Task<Void, Never>?
    private var refreshGeneration = 0

    init(client: any UnlimitedPurchasing, checkoutEnabled: Bool) {
        self.client = client
        self.checkoutEnabled = checkoutEnabled
        listener = Task { [weak self, client] in
            for await _ in client.updates() {
                guard !Task.isCancelled else { break }
                await self?.refreshEntitlements()
            }
        }
    }

    convenience init() {
        self.init(client: StoreKitUnlimitedPurchasing(), checkoutEnabled: UnlimitedProduct.liveCheckoutEnabled)
    }

    deinit { listener?.cancel() }

    var canPurchase: Bool {
        checkoutEnabled && hasCheckedEntitlements && !hasUnlimited && price != nil && !isBusy && !isLoadingOffer
    }

    func refreshEntitlements() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let owns = await client.hasEntitlement()
        guard generation == refreshGeneration else { return }
        hasUnlimited = owns
        hasCheckedEntitlements = true
    }

    func prepare() async {
        await refreshEntitlements()
        guard checkoutEnabled, !hasUnlimited, !isLoadingOffer else { return }
        isLoadingOffer = true
        defer { isLoadingOffer = false }
        message = nil
        do {
            price = try await client.displayPrice()
            if price == nil { message = PurchaseError.unavailable.localizedDescription }
        } catch {
            price = nil
            message = error.localizedDescription
        }
    }

    func purchase() async {
        guard canPurchase else { return }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            switch try await client.purchase() {
            case .completed:
                await refreshEntitlements()
                if !hasUnlimited { message = "Your purchase is processing. Try Restore Purchases in a moment." }
            case .pending:
                message = "Your purchase is awaiting approval. Unlimited will unlock when the App Store confirms it."
            case .cancelled: break
            }
        } catch { message = error.localizedDescription }
    }

    func restore() async {
        guard !isBusy else { return }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            try await client.restore()
            await refreshEntitlements()
            message = hasUnlimited ? "Unlimited restored." : "No Unlimited purchase was found for this App Store account."
        } catch { message = error.localizedDescription }
    }
}
