import Foundation
import Testing
@testable import Luminux

/// Answers every request with whatever the running test put in `response`.
nonisolated private final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var response: (status: Int, body: Data)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let response = Self.response, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct NewsFeedTests {
    private let endpoint = URL(string: "https://news.example.com/headlines")!

    private func freshDefaults() -> UserDefaults {
        let name = "NewsFeedTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func stubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }

    private let feedJSON = Data("""
    {
      "enabled": true,
      "attribution": "Headlines from GNews",
      "articles": [
        {"title": "First", "source": "BBC News", "url": "https://example.com/1", "publishedAt": "2026-10-08T09:30:00Z"},
        {"title": "Second", "source": "Reuters", "url": "https://example.com/2", "image": "https://example.com/2.jpg"}
      ]
    }
    """.utf8)

    @Test func decodesTheProxyResponse() throws {
        let feed = try NewsFeed.decode(feedJSON)

        #expect(feed.enabled)
        #expect(feed.attribution == "Headlines from GNews")
        #expect(feed.articles.map(\.title) == ["First", "Second"])
        #expect(feed.articles[0].publishedAt == ISO8601DateFormatter().date(from: "2026-10-08T09:30:00Z"))
        #expect(feed.articles[1].image == URL(string: "https://example.com/2.jpg"))
    }

    @Test func showsSampleHeadlinesWithoutAProxyInDebugBuilds() {
        let feed = NewsFeed(defaults: freshDefaults(), endpoint: nil)

        #expect(feed.usesSamples)
        #expect(feed.isEnabled)
        #expect(!feed.articles.isEmpty)
        #expect(feed.phase == .loaded)
    }

    @Test func loadsHeadlinesAndRemembersTheSwitch() async {
        StubProtocol.response = (200, feedJSON)
        let defaults = freshDefaults()
        let feed = NewsFeed(defaults: defaults, endpoint: endpoint, session: stubSession())
        #expect(!feed.isEnabled)

        await feed.refresh()

        #expect(feed.phase == .loaded)
        #expect(feed.articles.count == 2)
        #expect(NewsFeed(defaults: defaults, endpoint: endpoint, session: stubSession()).isEnabled)
    }

    @Test func remoteSwitchTurnsThePanelOff() async {
        StubProtocol.response = (200, Data(#"{"enabled": false, "articles": []}"#.utf8))
        let defaults = freshDefaults()
        defaults.set(true, forKey: "newsEnabled")
        let feed = NewsFeed(defaults: defaults, endpoint: endpoint, session: stubSession())
        #expect(feed.isEnabled)

        await feed.refresh()

        #expect(!feed.isEnabled)
    }

    @Test func keepsTheLastHeadlinesWhenOffline() async {
        StubProtocol.response = (200, feedJSON)
        let feed = NewsFeed(defaults: freshDefaults(), endpoint: endpoint, session: stubSession())
        await feed.refresh()

        StubProtocol.response = nil
        await feed.refresh()

        #expect(feed.phase == .loaded)
        #expect(feed.articles.count == 2)
    }

    @Test func showsAnErrorWhenNothingHasLoaded() async {
        StubProtocol.response = (500, Data())
        let feed = NewsFeed(defaults: freshDefaults(), endpoint: endpoint, session: stubSession())

        await feed.refresh()

        #expect(feed.phase == .failed)
        #expect(feed.articles.isEmpty)
    }
}
