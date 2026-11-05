import Photos
import PhotosUI
import SwiftUI

/// Settings' "background from" page: favorites, every photo, an album, a pinned photo set, or photos picked one by one.
/// Everything but favorites comes with Pro.
struct BackgroundPicker: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PhotoLibrary.self) private var library
    @Environment(HubTiles.self) private var hubTiles
    @Environment(ProStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @State private var picked: [PhotosPickerItem] = []
    @State private var showsPhotoPicker = false

    var body: some View {
        ChoicePage(title: "background", caption: "The hub shows a photo from here each time Luminux opens.") {
            option(.favorites, cover: library.favorites.firstObject, count: library.favorites.count)
            option(.everything, cover: library.allAssets.firstObject, count: library.allAssets.count)

            Button {
                if isLocked { openPro() } else { showsPhotoPicker = true }
            } label: {
                if case .photos(let ids) = Self.current(settings, store: store) {
                    ChoiceRow(cover: ids.first.flatMap(library.asset(id:)), title: "choose photos", detail: Self.name(for: .photos(ids), library: library, hubTiles: hubTiles), isSelected: true)
                } else {
                    ChoiceRow(cover: nil, systemImage: "plus", title: "choose photos", detail: "Pick the ones to rotate through", isSelected: false, isLocked: isLocked)
                }
            }
            .buttonStyle(TiltButtonStyle(touch: nil, size: .zero))

            if !library.albums.isEmpty {
                ChoiceHeader(title: "albums")
                ForEach(library.albums) { album in
                    option(.album(album.id), cover: album.keyAssetID.flatMap(library.asset(id:)), count: album.count)
                }
            }
            let sets = hubTiles.photoSets.values.sorted { $0.title < $1.title }
            if !sets.isEmpty {
                ChoiceHeader(title: "photo sets")
                ForEach(sets) { set in
                    option(.photoSet(set.id), cover: set.photoIDs.first.flatMap(library.asset(id:)), count: set.photoIDs.count)
                }
            }
        }
        .photosPicker(isPresented: $showsPhotoPicker, selection: $picked, maxSelectionCount: 50, matching: .images, photoLibrary: .shared())
        .onChange(of: picked) { _, items in
            // Only photos the app can read come back with an identifier.
            let ids = items.compactMap(\.itemIdentifier)
            guard !ids.isEmpty else { return }
            settings.hubBackground = .photos(ids)
        }
    }

    private var isLocked: Bool { !store.unlocksPro }

    /// The source in use: without Pro, always favorites, so a choice made before a refund comes back with Pro.
    static func current(_ settings: AppSettings, store: ProStore) -> HubBackgroundSource {
        store.unlocksPro ? settings.hubBackground : .favorites
    }

    private func openPro() { navigator.push(.pro) }

    private func option(_ source: HubBackgroundSource, cover: PHAsset?, count: Int) -> some View {
        let locked = isLocked && source != .favorites
        return Button {
            if locked { return openPro() }
            withAnimation(MetroMotion.fade) { settings.hubBackground = source }
        } label: {
            ChoiceRow(
                cover: cover,
                title: Self.name(for: source, library: library, hubTiles: hubTiles),
                detail: count == 1 ? "1 photo" : "\(count) photos",
                isSelected: Self.current(settings, store: store) == source,
                isLocked: locked
            )
        }
        .buttonStyle(TiltButtonStyle(touch: nil, size: .zero))
    }

    static func name(for source: HubBackgroundSource, library: PhotoLibrary, hubTiles: HubTiles) -> String {
        switch source {
        case .favorites: "favorites"
        case .everything: "all photos"
        case .album(let id): library.album(id: id)?.title ?? "album"
        case .photoSet(let id): hubTiles.photoSet(id: id)?.title ?? "photo set"
        case .photos(let ids): ids.count == 1 ? "1 chosen photo" : "\(ids.count) chosen photos"
        }
    }
}

/// A settings page that picks from a list: the page title over its choices, with a back button in the app bar
/// besides the edge swipe, so it's plain how to get out.
struct ChoicePage<Content: View>: View {
    let title: String
    var caption: String?
    @ViewBuilder var content: Content

    @Environment(Navigator.self) private var navigator
    @Environment(\.metro) private var metro
    @State private var isAppBarExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("LUMINUX · SETTINGS").font(.metroOverline).tracking(1.5).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    Text(title)
                        .font(.metroTitle)
                        .padding(.leading, -3)
                        .accessibilityAddTraits(.isHeader)
                    if let caption {
                        Text(caption)
                            .font(.metroCaption)
                            .foregroundStyle(metro.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.bottom, 20)
                .metroFeather(row: 0)

                VStack(alignment: .leading, spacing: 0) { content }.metroFeather(row: 1)
            }
            .padding(.horizontal, MetroMetrics.margin + 12)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(metro.foreground)
        .background(metro.background)
        .metroAppBar([AppBarButton(title: "back", systemImage: "arrow.left") { navigator.pop() }], menu: [], isExpanded: $isAppBarExpanded)
    }
}

/// One choice: its cover photo, name and count, in the accent with a check when it's the one in use.
struct ChoiceRow: View {
    let cover: PHAsset?
    var systemImage = "photo"
    let title: String
    let detail: String?
    let isSelected: Bool
    var isLocked = false
    var isBusy = false

    @Environment(\.metro) private var metro
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let cover {
                    AssetThumbnail(asset: cover, pixelSide: 56 * displayScale)
                } else {
                    metro.chrome.overlay {
                        Image(systemName: systemImage)
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(metro.secondary)
                    }
                }
            }
            .frame(width: 56, height: 56)
            .clipped()
            .overlay { if isSelected { Rectangle().strokeBorder(metro.accentColor, lineWidth: 3) } }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.metro(22, .semilight))
                        .foregroundStyle(isSelected ? metro.accentColor : metro.foreground)
                        .lineLimit(1)
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12, weight: .light))
                            .foregroundStyle(metro.secondary)
                            .accessibilityLabel("needs Luminux Pro")
                    }
                }
                if let detail {
                    Text(detail).font(.metroCaption).foregroundStyle(metro.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if isBusy {
                ProgressView()
            } else if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(metro.accentColor)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

struct ChoiceHeader: View {
    let title: String
    @Environment(\.metro) private var metro

    var body: some View {
        Text(title)
            .font(.metro(20, .semilight))
            .foregroundStyle(metro.secondary)
            .padding(.top, 24)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}
