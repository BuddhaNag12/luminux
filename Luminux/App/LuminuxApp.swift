import SwiftUI

@main
struct LuminuxApp: App {
    @State private var settings = AppSettings()
    @State private var library = PhotoLibrary()
    @State private var navigator = Navigator()
    @State private var store = ProStore()
    @State private var journal = Journal()
    @State private var hubTiles = HubTiles()
    @State private var news = NewsFeed()
    @State private var adConsent: AdConsent
    @State private var newsAds: NewsAds
    @State private var rewardedAds: RewardedAds

    init() {
        let consent = AdConsent()
        _adConsent = State(initialValue: consent)
        _newsAds = State(initialValue: NewsAds(consent: consent))
        _rewardedAds = State(initialValue: RewardedAds(consent: consent))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(library)
                .environment(navigator)
                .environment(store)
                .environment(journal)
                .environment(hubTiles)
                .environment(news)
                .environment(adConsent)
                .environment(newsAds)
                .environment(rewardedAds)
                .environment(\.metro, settings.palette)
                .tint(settings.accent.color)
                .preferredColorScheme(settings.theme.colorScheme)
        }
    }
}

struct RootView: View {
    @Environment(PhotoLibrary.self) private var library

    var body: some View {
        #if DEBUG
        if let gallery = ComponentGallery.requested {
            ComponentGallery(kind: gallery)
        } else {
            content
        }
        #else
        content
        #endif
    }

    @ViewBuilder private var content: some View {
        if library.access.canRead {
            AppShell()
        } else {
            PermissionView()
        }
    }
}

private struct AppShell: View {
    @Environment(Navigator.self) private var navigator
    @Environment(PhotoLibrary.self) private var library
    @Environment(AppSettings.self) private var settings
    @Environment(ProStore.self) private var store
    @Environment(Journal.self) private var journal
    @Environment(HubTiles.self) private var hubTiles
    @Namespace private var zoom

    var body: some View {
        @Bindable var navigator = navigator

        MetroStack {
            HubView()
        } destination: { route in
            switch route {
            case .collection(let page, let showsJumpList):
                CollectionView(page: page, showsJumpList: showsJumpList)
            case .album(let id):
                AlbumView(albumID: id)
            case .settings:
                SettingsView()
            case .pro:
                ProView()
            case .about:
                AboutView()
            case .journal:
                JournalView()
            case .journalEntry(let id):
                JournalEntryView(entryID: id)
            case .photoSet(let id):
                PhotoSetView(setID: id)
            }
        }
        .environment(\.zoomNamespace, zoom)
        .fullScreenCover(item: $navigator.viewer) { request in
            ViewerView(request: request)
                .navigationTransition(.zoom(sourceID: navigator.viewerCurrentID ?? request.startID, in: zoom))
        }
        .onOpenURL { url in
            // The live tile opens the hub or its collection; a locked wide tile opens the Pro page.
            navigator.viewer = nil
            if url.host() == "pro" && !store.isUnlocked {
                navigator.path = [.pro]
            } else if url.host() == "collection",
                      let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value {
                if id.hasPrefix("album:") {
                    navigator.path = [.album(String(id.dropFirst("album:".count)))]
                } else if id.hasPrefix("set:") {
                    navigator.path = [.photoSet(String(id.dropFirst("set:".count)))]
                } else {
                    navigator.path = []
                }
            } else {
                navigator.path = []
            }
        }
        .task {
            await store.refresh()
        }
        .task(id: JournalRefreshKey(changeToken: library.changeToken, namesPlaces: settings.namesJournalPlaces)) {
            guard library.isLoaded else { return }
            journal.usesPlaceNames = settings.namesJournalPlaces
            // Debounce bursts of library changes, like the live tile.
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await journal.rebuild()
            if settings.namesJournalPlaces { await journal.lookUpPlaces() }
        }
        .task(id: library.changeToken) {
            // Deleted albums leave the hub too.
            guard library.isLoaded else { return }
            hubTiles.prune(albumIDs: Set(library.albums.map(\.id)))
        }
        .onChange(of: store.unlocksCustomAccent) { _, unlocked in
            // A refunded purchase takes its custom colour with it.
            if !unlocked && !settings.accent.isPreset { settings.accent = .cobalt }
        }
        .task(id: TileRefreshKey(changeToken: library.changeToken, accent: settings.accent)) {
            guard library.isLoaded else { return }
            // Debounce bursts of library changes.
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await LiveTileExporter.export(from: library, hubTiles: hubTiles, accent: settings.accent)
        }
    }
}

private struct JournalRefreshKey: Equatable {
    let changeToken: Int
    let namesPlaces: Bool
}

private struct TileRefreshKey: Equatable {
    let changeToken: Int
    let accent: Accent
}
