import GoogleMobileAds
import SwiftUI

/// The hub's left-most panel: headlines with a native ad after every few. Pro hides it.
struct NewsPanel: View {
    @Environment(NewsFeed.self) private var feed
    @Environment(NewsAds.self) private var ads
    @Environment(Navigator.self) private var navigator
    @Environment(\.metro) private var metro

    private enum Row: Identifiable {
        case article(NewsArticle)
        case ad(NativeAd)

        var id: String {
            switch self {
            case .article(let article): article.url.absoluteString
            case .ad(let ad): "ad-\(ObjectIdentifier(ad).hashValue)"
            }
        }
    }

    private var rows: [Row] {
        var rows: [Row] = []
        var remainingAds = ads.ads[...]
        for (index, article) in feed.articles.enumerated() {
            rows.append(.article(article))
            if (index + 1) % NewsAds.headlinesPerAd == 0, let ad = remainingAds.popFirst() {
                rows.append(.ad(ad))
            }
        }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            switch feed.phase {
            case .idle, .loading where feed.articles.isEmpty:
                Text("Getting the headlines…")
                    .font(.metroBody)
                    .foregroundStyle(metro.foreground.opacity(0.75))
                    .metroFeather(row: 2)
            case .failed:
                VStack(alignment: .leading, spacing: 12) {
                    Text("Couldn't reach the news. Check your connection.")
                        .font(.metroBody)
                        .foregroundStyle(metro.foreground.opacity(0.75))
                    Button("try again") { Task { await feed.refresh() } }
                        .buttonStyle(.metro)
                }
                .metroFeather(row: 2)
            default:
                EmptyView()
            }

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                Group {
                    switch row {
                    case .article(let article): headline(article)
                    case .ad(let ad): adBlock(ad)
                    }
                }
                .metroFeather(row: 2 + index)
            }

            if let attribution = feed.attribution, !feed.articles.isEmpty {
                Text(attribution)
                    .font(.metroCaption)
                    .foregroundStyle(metro.foreground.opacity(0.6))
            }
        }
        .padding(.trailing, MetroMetrics.margin + 12)
    }

    private func headline(_ article: NewsArticle) -> some View {
        Button {
            UIApplication.shared.openInApp(article.url, tint: UIColor(metro.accentColor))
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(article.title)
                        .font(.metro(20, .semilight, relativeTo: .title3))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(byline(article))
                        .font(.metroCaption)
                        .foregroundStyle(metro.accentColor)
                }
                Spacer(minLength: 0)
                if let image = article.image {
                    AsyncImage(url: image) { picture in
                        picture.resizable().scaledToFill()
                    } placeholder: {
                        metro.chrome
                    }
                    .frame(width: 72, height: 72)
                    .clipped()
                    .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the story")
    }

    private func byline(_ article: NewsArticle) -> String {
        guard let date = article.publishedAt else { return article.source }
        return "\(article.source) · \(date.formatted(.relative(presentation: .named)))"
    }

    private func adBlock(_ ad: NativeAd) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            NativeAdCard(ad: ad, palette: metro)
            Button {
                navigator.push(.pro)
            } label: {
                Text("remove ads with pro")
                    .font(.metro(15, .semilight))
                    .underline()
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
