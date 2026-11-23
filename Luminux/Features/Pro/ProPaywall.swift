import StoreKit
import SwiftUI

/// The paywall shown once, right after the first-run tour, in the system's style rather than Metro.
/// The close button fades in after a few seconds so the offer gets a look; with VoiceOver it's there at once.
struct ProPaywall: View {
    var onClose: () -> Void

    @Environment(ProStore.self) private var store
    @Environment(\.purchase) private var purchase
    @Environment(\.metro) private var metro
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var showsClose = false
    @State private var isRedeeming = false

    private static let closeDelay = Duration.seconds(3)

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                LogoMark(unit: 1.1, cutout: metro.background)
                    .padding(.top, 48)
                    .accessibilityHidden(true)
                Text("Luminux Pro")
                    .font(.largeTitle.bold())
                    .padding(.top, 20)
                    .accessibilityAddTraits(.isHeader)
                Text("Every feature, and no ads.")
                    .font(.body)
                    .foregroundStyle(metro.secondary)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 18) {
                    ForEach(ProPitch.perks) { perk in
                        perkRow(perk)
                    }
                }
                .padding(.top, 32)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) { purchaseBar }
        .overlay(alignment: .topTrailing) {
            if showsClose { closeButton }
        }
        .foregroundStyle(metro.foreground)
        .background(metro.background)
        .task {
            if !voiceOver { try? await Task.sleep(for: Self.closeDelay) }
            withAnimation(.easeIn(duration: 0.4)) { showsClose = true }
        }
        .task { await store.refresh() }
        // A purchase, restore or redeemed code closes the offer.
        .onChange(of: store.isUnlocked) { _, unlocked in
            if unlocked { onClose() }
        }
    }

    private func perkRow(_ perk: ProPitch.Perk) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: perk.glyph)
                .font(.title2)
                .foregroundStyle(metro.accentColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                // The Metro titles are lower case; this screen uses sentence case.
                Text(perk.title.prefix(1).uppercased() + perk.title.dropFirst())
                    .font(.headline)
                Text(perk.detail)
                    .font(.subheadline)
                    .foregroundStyle(metro.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var purchaseBar: some View {
        VStack(spacing: 8) {
            // Without a product the button retries the load, as on the Pro page.
            Button {
                Task {
                    if store.product == nil { await store.refresh() } else { await store.purchase(with: purchase) }
                }
            } label: {
                Text(store.isPurchasing ? "Unlocking…"
                     : store.product.map { "Unlock for \($0.displayPrice)" } ?? "Try again")
                    .font(.headline)
                    .foregroundStyle(metro.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(metro.accentColor, in: .rect(cornerRadius: 14, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.isPurchasing)

            Text(store.product == nil ? "Can't reach the App Store right now." : "One payment, yours for good. No subscription.")
                .font(.footnote)
                .foregroundStyle(metro.secondary)
                .multilineTextAlignment(.center)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) { restoreLink; redeemLink }
                VStack(spacing: 0) { restoreLink; redeemLink }
            }
            .offerCodeRedemption(isPresented: $isRedeeming) { _ in
                // If the sheet couldn't open, this lets the next tap try again.
                isRedeeming = false
                Task { await store.refresh() }
            }

            if let message = store.message {
                Text(message)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .background(metro.background)
    }

    private var restoreLink: some View {
        Button("Restore purchase") { Task { await store.restore() } }
            .font(.subheadline)
            .foregroundStyle(metro.accentColor)
            .frame(minHeight: 44)
    }

    private var redeemLink: some View {
        Button("Redeem a code") { isRedeeming = true }
            .font(.subheadline)
            .foregroundStyle(metro.accentColor)
            .frame(minHeight: 44)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(metro.secondary)
                .frame(width: 30, height: 30)
                .background(metro.foreground.opacity(0.1), in: .circle)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        .padding(.trailing, 10)
        .transition(.opacity)
    }
}
