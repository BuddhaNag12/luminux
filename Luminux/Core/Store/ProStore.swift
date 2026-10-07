import StoreKit
import SwiftUI
import WidgetKit

/// The one-time "Luminux Pro" purchase: every accent, the medium and large live tiles, the slideshow and editing.
@Observable
final class ProStore {
    static let productID = "com.buddhanag.luminux.pro"

    private(set) var isUnlocked: Bool
    private(set) var product: Product?
    private(set) var isPurchasing = false
    /// Set when a purchase or restore needs explaining; the Pro page shows it.
    var message: String?

    @ObservationIgnored private var updates: Task<Void, Never>?

    init() {
        // The last known state, so Pro features don't flicker off while the App Store answers.
        isUnlocked = LiveTileStore.isPro
        updates = Task { [weak self] in
            // Purchases made on another device, Ask to Buy approvals and refunds arrive here.
            for await result in StoreKit.Transaction.updates {
                await self?.handle(result)
            }
        }
    }

    /// Loads the product and checks the purchase against the App Store's signed receipts.
    func refresh() async {
        if product == nil {
            product = try? await Product.products(for: [Self.productID]).first
        }
        var unlocked = false
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == Self.productID, transaction.revocationDate == nil {
                unlocked = true
            }
        }
        setUnlocked(unlocked)
    }

    func purchase(with action: PurchaseAction) async {
        guard let product, !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        message = nil
        do {
            switch try await action(product) {
            case .success(let result):
                guard case .verified(let transaction) = result else {
                    message = "The App Store couldn't confirm the purchase. Try restoring it."
                    return
                }
                setUnlocked(true)
                await transaction.finish()
            case .pending:
                message = "The purchase is waiting for approval. Pro unlocks as soon as it's approved."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = "The purchase didn't go through. Check your connection and try again."
        }
    }

    func restore() async {
        message = nil
        try? await AppStore.sync()
        await refresh()
        if !isUnlocked {
            message = "No Luminux Pro purchase was found for this Apple Account."
        }
    }

    private func handle(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = result, transaction.productID == Self.productID else { return }
        setUnlocked(transaction.revocationDate == nil)
        await transaction.finish()
    }

    private func setUnlocked(_ unlocked: Bool) {
        if isUnlocked != unlocked { isUnlocked = unlocked }
        guard LiveTileStore.isPro != unlocked else { return }
        LiveTileStore.isPro = unlocked
        WidgetCenter.shared.reloadAllTimelines()
    }
}

extension Accent {
    /// The classic six stay free; Pro unlocks the rest.
    static let free: [Accent] = [.cobalt, .lime, .teal, .magenta, .red, .mango]

    var isFree: Bool { Self.free.contains(self) }
}
