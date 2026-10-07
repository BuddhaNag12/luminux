import StoreKitTest
import Testing
@testable import Luminux

@Suite(.serialized)
struct ProStoreTests {
    private func freshSession() throws -> SKTestSession {
        let session = try SKTestSession(configurationFileNamed: "Luminux")
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        return session
    }

    /// The local StoreKit service catches up asynchronously (most of all on a bundle's first run), so give it a moment.
    private func refresh(_ store: ProStore, until condition: () -> Bool) async {
        for _ in 0..<50 {
            await store.refresh()
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    @Test func loadsTheProductLocked() async throws {
        _ = try freshSession()
        let store = ProStore()
        await refresh(store) { store.product != nil }

        #expect(store.product?.id == ProStore.productID)
        #expect(!store.isUnlocked)
    }

    @Test func buyingUnlocksAndARefundLocksAgain() async throws {
        let session = try freshSession()
        let store = ProStore()
        try await session.buyProduct(identifier: ProStore.productID)
        await refresh(store) { store.isUnlocked }
        #expect(store.isUnlocked)

        let purchase = try #require(session.allTransactions().first { $0.productIdentifier == ProStore.productID })
        try session.refundTransaction(identifier: purchase.identifier)
        await refresh(store) { !store.isUnlocked }
        #expect(!store.isUnlocked)
    }
}
