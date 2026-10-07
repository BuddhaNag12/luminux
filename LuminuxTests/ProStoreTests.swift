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

    @Test func loadsTheProductLocked() async throws {
        _ = try freshSession()
        let store = ProStore()
        await store.refresh()

        #expect(store.product?.id == ProStore.productID)
        #expect(!store.isUnlocked)
    }

    @Test func buyingUnlocksAndClearingLocksAgain() async throws {
        let session = try freshSession()
        let store = ProStore()
        try await session.buyProduct(identifier: ProStore.productID)
        await store.refresh()
        #expect(store.isUnlocked)

        session.clearTransactions()
        await store.refresh()
        #expect(!store.isUnlocked)
    }

    @Test func onlyTheClassicSixAccentsAreFree() {
        #expect(Accent.allCases.filter(\.isFree).count == 6)
        #expect(Accent.cobalt.isFree)
        #expect(!Accent.violet.isFree)
    }
}
