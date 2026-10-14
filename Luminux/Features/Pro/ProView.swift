import StoreKit
import SwiftUI

/// What Pro adds and the button that buys it, shown in the hub's last panel and on the Pro page.
struct ProPitch: View {
    /// The feather line of the first perk.
    var firstRow = 0

    @Environment(ProStore.self) private var store
    @Environment(\.purchase) private var purchase
    @Environment(\.metro) private var metro

    private struct Perk: Identifiable {
        let glyph: String
        let title: String
        let detail: String
        var id: String { title }
    }

    private let perks = [
        Perk(glyph: "play.slash", title: "no ads", detail: "Use every feature without watching an ad."),
        Perk(glyph: "paintpalette", title: "any accent colour", detail: "Pick your own accent, beyond the classic six."),
        Perk(glyph: "rectangle.split.2x1", title: "wide live tiles", detail: "Medium and large photo tiles for the home screen."),
        Perk(glyph: "pin", title: "unlimited pins", detail: "Pin as many albums and photo sets to the hub as you like."),
        Perk(glyph: "play.rectangle", title: "slideshow", detail: "A slow pan and zoom through any collection."),
        Perk(glyph: "person.crop.rectangle.stack", title: "lift subjects", detail: "Touch and hold a person or pet to copy, share or drag it out."),
        Perk(glyph: "slider.horizontal.3", title: "editing", detail: "Crop, light, colour and looks, saved back to your library and editable later."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.isUnlocked {
                unlockedCard
                    .metroFeather(row: firstRow)
            } else {
                offerCard
                    .metroFeather(row: firstRow)
                    .padding(.bottom, 16)

                Text("what you get")
                    .font(.metro(22, .semilight))
                    .foregroundStyle(metro.secondary)
                    .padding(.bottom, 4)
                    .accessibilityAddTraits(.isHeader)
                    .metroFeather(row: firstRow + 1)

                VStack(spacing: 0) {
                    ForEach(Array(perks.enumerated()), id: \.element.id) { index, perk in
                        perkRow(perk, isFirst: index == 0)
                            .metroFeather(row: firstRow + 2 + index)
                    }
                }
                // Slightly see-through, so the hub's photo shows behind the list in its Pro panel.
                .background(metro.chrome.opacity(0.92))
            }

            if let message = store.message {
                Text(message)
                    .font(.metroCaption)
                    .foregroundStyle(metro.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
        }
        .task { await store.refresh() }
    }

    /// The price and the buy button on an accent block, so the offer is the first thing on the page.
    private var offerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LUMINUX PRO").font(.metroOverline).tracking(1.5)
            Text(store.product?.displayPrice ?? "pro")
                .font(.metro(48, .light))
                .padding(.top, 10)
            Text(store.product == nil
                 ? "Can't reach the App Store right now."
                 : "One payment, yours for good. No subscription, no ads.")
                .font(.metroCaption)
                .opacity(0.9)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task { await store.purchase(with: purchase) }
            } label: {
                Text(store.isPurchasing ? "unlocking…" : "unlock pro")
                    .font(.metro(17, .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(.white)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TiltButtonStyle(touch: nil, size: .zero))
            .disabled(store.product == nil || store.isPurchasing)
            .opacity(store.product == nil ? 0.5 : 1)
            .padding(.top, 20)
            .accessibilityLabel(store.product.map { "Unlock Pro for \($0.displayPrice)" } ?? "Unlock Pro")

            Button {
                Task { await store.restore() }
            } label: {
                Text("restore purchase")
                    .font(.metro(15, .semilight))
                    .underline()
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .foregroundStyle(.white)
        .padding(20)
        .padding(.bottom, -8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(metro.accentColor)
    }

    private var unlockedCard: some View {
        HStack(spacing: 14) {
            metro.accentColor
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text("pro unlocked").font(.metro(20, .semilight))
                Text("Thank you for supporting Luminux.")
                    .font(.metroCaption)
                    .foregroundStyle(metro.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(metro.chrome)
        .accessibilityElement(children: .combine)
    }

    private func perkRow(_ perk: Perk, isFirst: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: perk.glyph)
                .font(.system(size: 20, weight: .light))
                // Not the accent: dark accents are too dim on the panel.
                .foregroundStyle(metro.foreground)
                .frame(width: 28)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(perk.title).font(.metro(17, .semilight))
                Text(perk.detail)
                    .font(.metroCaption)
                    .foregroundStyle(metro.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            if !isFirst {
                Rectangle().fill(metro.foreground.opacity(0.12)).frame(height: 1).padding(.leading, 56)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A locked feature the Pro page offers to unlock once for a rewarded ad.
struct ProTrial {
    /// The heading, e.g. "play a slideshow once".
    let title: String
    let onEarned: () -> Void
}

/// The Pro page, pushed from settings and the widget, or shown over the viewer.
struct ProView: View {
    /// Offered above the purchase when the page opens from a locked feature.
    var trial: ProTrial?
    /// Closes the page when it's shown over the viewer; a pushed page goes back with the usual swipe.
    var onClose: (() -> Void)?

    @Environment(ProStore.self) private var store
    @Environment(RewardedAds.self) private var rewardedAds
    @Environment(\.metro) private var metro

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("LUMINUX").font(.metroOverline).tracking(1.5)
                    .metroFeather(row: 0)
                Text("pro")
                    .font(.metroTitle)
                    .padding(.leading, -3)
                    .metroFeather(row: 0)
                    .padding(.bottom, 24)

                if let trial, !store.isUnlocked {
                    tryOnce(trial)
                        .metroFeather(row: 1)
                        .padding(.bottom, 24)
                }

                ProPitch(firstRow: trial == nil ? 1 : 2)

                // With an ad offer, "not now" sits beside it instead.
                if let onClose, store.isUnlocked || trial == nil {
                    Button(store.isUnlocked ? "done" : "not now", action: onClose)
                        .buttonStyle(.metro)
                        .padding(.top, 32)
                }
            }
            .padding(.horizontal, MetroMetrics.margin + 12)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(metro.foreground)
        .background(metro.background)
        .task {
            guard trial != nil, !store.isUnlocked else { return }
            rewardedAds.clearMessage()
            await rewardedAds.preload()
        }
    }

    /// The quick way in when the page opened from a locked feature: one ad for one use.
    private func tryOnce(_ trial: ProTrial) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(trial.title).font(.metro(20, .semilight))
            Text("Watch a short ad to use it now, or unlock Pro below and never see one.")
                .font(.metroCaption)
                .foregroundStyle(metro.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button {
                    Task {
                        if await rewardedAds.watch() { trial.onEarned() }
                    }
                } label: {
                    Text(rewardedAds.isLoading ? "loading ad…" : "watch an ad")
                        .font(.metro(20, .semilight))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 6)
                        .frame(minHeight: 56)
                }
                .buttonStyle(.metro)
                .disabled(rewardedAds.isLoading)
                if let onClose {
                    Button(action: onClose) {
                        Text("not now")
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.metro)
                }
            }
            if let message = rewardedAds.message {
                Text(message)
                    .font(.metroCaption)
                    .foregroundStyle(metro.accentColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Rectangle().strokeBorder(metro.foreground.opacity(0.35), lineWidth: 1))
    }
}
