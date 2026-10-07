import Foundation
import Observation

nonisolated struct NewsArticle: Identifiable, Hashable, Decodable, Sendable {
    let title: String
    let source: String
    let url: URL
    var image: URL?
    var publishedAt: Date?

    var id: URL { url }
}

/// What the news proxy (`Server/news-worker`) returns. `enabled` is the remote switch for the whole panel.
nonisolated struct NewsResponse: Decodable, Sendable {
    var enabled: Bool
    var articles: [NewsArticle]
    /// Credit line the news provider asks for, e.g. "Headlines from GNews".
    var attribution: String?
}

/// Headlines for the hub's news panel, fetched from Luminux's own proxy so the provider's key stays off the phone and
/// the provider never sees who's reading.
@Observable
final class NewsFeed {
    enum Phase: Equatable {
        case idle, loading, loaded, failed
    }

    private(set) var articles: [NewsArticle] = []
    private(set) var attribution: String?
    private(set) var phase = Phase.idle
    /// Remembered between launches so the panel doesn't pop in on the left after the hub is already laid out.
    private(set) var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let endpoint: URL?
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var fetchedAt: Date?

    private static let enabledKey = "newsEnabled"
    /// The proxy caches for this long too, so fetching sooner only returns the same headlines.
    static let refreshInterval: TimeInterval = 15 * 60

    /// Without a proxy URL, debug and test builds show placeholder headlines so the panel can be checked; App Store
    /// builds hide the panel.
    var usesSamples: Bool {
        #if DEBUG
        endpoint == nil
        #else
        endpoint == nil && ProStore.isTestBuild
        #endif
    }

    init(defaults: UserDefaults = .standard, endpoint: URL? = NewsFeed.configuredEndpoint, session: URLSession = .shared) {
        self.defaults = defaults
        self.endpoint = endpoint
        self.session = session
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        if usesSamples {
            isEnabled = true
            articles = Self.samples
            attribution = "Sample headlines: the news feed isn't connected yet."
            phase = .loaded
        }
    }

    static var configuredEndpoint: URL? {
        guard let string = Bundle.main.object(forInfoDictionaryKey: "LuminuxNewsURL") as? String, !string.isEmpty else { return nil }
        return URL(string: string)
    }

    func refreshIfStale() async {
        if let fetchedAt, Date.now.timeIntervalSince(fetchedAt) < Self.refreshInterval { return }
        await refresh()
    }

    func refresh() async {
        guard let endpoint, phase != .loading else { return }
        if articles.isEmpty { phase = .loading }
        do {
            let (data, response) = try await session.data(from: endpoint)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let feed = try Self.decode(data)
            isEnabled = feed.enabled
            articles = feed.articles
            attribution = feed.attribution
            fetchedAt = .now
            phase = .loaded
        } catch {
            // Keep the last headlines on screen; only an empty panel shows the error.
            phase = articles.isEmpty ? .failed : .loaded
        }
    }

    nonisolated static func decode(_ data: Data) throws -> NewsResponse {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(NewsResponse.self, from: data)
    }

    private static let samples: [NewsArticle] = (1...12).map { number in
        NewsArticle(
            title: "Sample headline \(number): real stories appear here once the news feed is connected",
            source: "luminux",
            url: URL(string: "https://example.com/\(number)")!,
            publishedAt: Date.now.addingTimeInterval(Double(-number) * 47 * 60)
        )
    }
}
