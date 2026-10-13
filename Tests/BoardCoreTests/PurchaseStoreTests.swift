import XCTest

@MainActor
private final class FakePurchasing: UnlimitedPurchasing {
    var entitled = false
    var offer: String? = "$1.99"
    var outcome: UnlimitedPurchaseOutcome = .completed
    var failure: Error?
    var restoreEntitlement = false
    var purchaseCount = 0
    var continuation: AsyncStream<Void>.Continuation?
    func displayPrice() async throws -> String? {
        if let failure { throw failure }; return offer
    }
    func hasEntitlement() async -> Bool { entitled }
    func purchase() async throws -> UnlimitedPurchaseOutcome {
        purchaseCount += 1
        if let failure { throw failure }
        if case .completed = outcome { entitled = true }
        return outcome
    }
    func restore() async throws {
        if let failure { throw failure }; entitled = restoreEntitlement
    }
    func updates() -> AsyncStream<Void> {
        AsyncStream { continuation = $0 }
    }
}

final class PurchaseStoreTests: XCTestCase {
    @MainActor func testPurchaseOnlyUnlocksAfterConfirmation() async {
        let client = FakePurchasing()
        let store = PurchaseStore(client: client, checkoutEnabled: true)
        XCTAssertFalse(store.canPurchase)
        await store.prepare()
        XCTAssertTrue(store.canPurchase)
        await store.purchase()
        XCTAssertTrue(store.hasUnlimited)
        XCTAssertFalse(store.canPurchase)
        await store.purchase()
        XCTAssertEqual(client.purchaseCount, 1)
    }

    @MainActor func testCancelledPendingAndFailedPurchasesRemainFree() async {
        let client = FakePurchasing()
        let store = PurchaseStore(client: client, checkoutEnabled: true)
        await store.prepare()
        client.outcome = .cancelled
        await store.purchase()
        XCTAssertFalse(store.hasUnlimited)
        XCTAssertNil(store.message)
        client.outcome = .pending
        await store.purchase()
        XCTAssertFalse(store.hasUnlimited)
        XCTAssertTrue(store.message?.contains("awaiting approval") == true)
        client.failure = NSError(domain: "UnverifiedTransaction", code: 1)
        await store.purchase()
        XCTAssertFalse(store.hasUnlimited)
        XCTAssertNotNil(store.message)
        XCTAssertFalse(store.isBusy)
    }

    @MainActor func testRestoreAndExpiredAccessRefreshWithoutLosingData() async {
        let client = FakePurchasing()
        let store = PurchaseStore(client: client, checkoutEnabled: true)
        client.restoreEntitlement = true
        await store.restore()
        XCTAssertTrue(store.hasUnlimited)
        client.entitled = false // StoreKit removes expired/refunded subscriptions.
        await store.refreshEntitlements()
        XCTAssertFalse(store.hasUnlimited)
        client.restoreEntitlement = false
        await store.restore()
        XCTAssertTrue(store.message?.contains("No Unlimited purchase") == true)
    }

    @MainActor func testMissingProductAndOfflineFetchCannotCharge() async {
        let client = FakePurchasing()
        let store = PurchaseStore(client: client, checkoutEnabled: true)
        client.offer = nil
        await store.prepare()
        XCTAssertFalse(store.canPurchase)
        await store.purchase()
        XCTAssertEqual(client.purchaseCount, 0)
        client.failure = URLError(.notConnectedToInternet)
        await store.prepare()
        XCTAssertFalse(store.canPurchase)
        XCTAssertNotNil(store.message)
        // Existing verified access remains usable even without a price/network response.
        client.entitled = true
        await store.prepare()
        XCTAssertTrue(store.hasUnlimited)
    }

    @MainActor func testTransactionUpdatesUnlockPendingAndRemoveRefundedAccess() async {
        let client = FakePurchasing()
        let store = PurchaseStore(client: client, checkoutEnabled: true)
        await store.prepare()
        for _ in 0..<100 where client.continuation == nil { await Task.yield() }
        XCTAssertNotNil(client.continuation)
        client.entitled = true
        client.continuation?.yield(())
        for _ in 0..<100 where !store.hasUnlimited { await Task.yield() }
        XCTAssertTrue(store.hasUnlimited)
        client.entitled = false
        client.continuation?.yield(())
        for _ in 0..<100 where store.hasUnlimited { await Task.yield() }
        XCTAssertFalse(store.hasUnlimited)
    }
}
