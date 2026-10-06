import SwiftUI

@main
struct LuminuxApp: App {
    @State private var settings = AppSettings()
    @State private var library = PhotoLibrary()
    @State private var navigator = Navigator()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(library)
                .environment(navigator)
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
            }
        }
        .environment(\.zoomNamespace, zoom)
        .fullScreenCover(item: $navigator.viewer) { request in
            ViewerView(request: request)
                .navigationTransition(.zoom(sourceID: navigator.viewerCurrentID ?? request.startID, in: zoom))
        }
        .onOpenURL { _ in
            // The live tile opens the hub.
            navigator.viewer = nil
            navigator.path = []
        }
        .task(id: TileRefreshKey(changeToken: library.changeToken, accent: settings.accent)) {
            guard library.isLoaded else { return }
            // Debounce bursts of library changes.
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await LiveTileExporter.export(from: library, accent: settings.accent)
        }
    }
}

private struct TileRefreshKey: Equatable {
    let changeToken: Int
    let accent: Accent
}
