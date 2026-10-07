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
        Perk(glyph: "play.rectangle", title: "slideshow", detail: "A slow pan and zoom through any collection."),
        Perk(glyph: "crop.rotate", title: "editing", detail: "Rotate and crop, saved back to your library."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if store.isUnlocked {
                Text("Pro is unlocked. Thank you for supporting Luminux.")
                    .font(.metroBody)
                    .foregroundStyle(metro.secondary)
                    .metroFeather(row: firstRow)
            } else {
                ForEach(Array(perks.enumerated()), id: \.element.id) { index, perk in
                    HStack(alignment: .top, spacing: 14) {
                        metro.accentColor
                            .frame(width: 48, height: 48)
                            .overlay {
                                Image(systemName: perk.glyph)
                                    .font(.system(size: 20, weight: .light))
                                    .foregroundStyle(.white)
                            }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(perk.title).font(.metro(20, .semilight))
                            // Brighter than the usual secondary text, so it reads over the hub's photo.
                            Text(perk.detail)
                                .font(.metroCaption)
                                .foregroundStyle(metro.foreground.opacity(0.75))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .metroFeather(row: firstRow + index)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Button(store.product.map { "unlock for \($0.displayPrice)" } ?? "unlock") {
                        Task { await store.purchase(with: purchase) }
                    }
                    .buttonStyle(.metro)
                    .disabled(store.product == nil || store.isPurchasing)
                    .opacity(store.product == nil ? 0.4 : 1)

                    Text(store.product == nil
                         ? "Can't reach the App Store right now."
                         : "One payment, yours for good. No subscription.")
                        .font(.metroCaption)
                        .foregroundStyle(metro.foreground.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        Task { await store.restore() }
                    } label: {
                        Text("restore purchase")
                            .font(.metro(17, .semilight))
                            .underline()
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .metroFeather(row: firstRow + perks.count)
            }

            if let message = store.message {
                Text(message)
                    .font(.metroCaption)
                    .foregroundStyle(metro.accentColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { await store.refresh() }
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
                        .padding(.bottom, 32)
                }

                ProPitch(firstRow: trial == nil ? 1 : 2)

                if let onClose {
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

    private func tryOnce(_ trial: ProTrial) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(trial.title).font(.metro(20, .semilight))
            Text("Watch a short ad to use it now, or unlock Pro below and never see one.")
                .font(.metroCaption)
                .foregroundStyle(metro.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(rewardedAds.isLoading ? "loading ad…" : "watch an ad") {
                Task {
                    if await rewardedAds.watch() { trial.onEarned() }
                }
            }
            .buttonStyle(.metro)
            .disabled(rewardedAds.isLoading)
            if let message = rewardedAds.message {
                Text(message)
                    .font(.metroCaption)
                    .foregroundStyle(metro.accentColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
