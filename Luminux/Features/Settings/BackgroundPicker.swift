import PhotosUI
import SwiftUI

/// Settings' "background from" sheet: favorites, every photo, an album, a pinned photo set, or photos picked one by one.
/// Everything but favorites comes with Pro.
struct BackgroundPicker: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PhotoLibrary.self) private var library
    @Environment(HubTiles.self) private var hubTiles
    @Environment(ProStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @Environment(\.metro) private var metro
    @Environment(\.dismiss) private var dismiss
    @State private var picked: [PhotosPickerItem] = []
    @State private var showsPhotoPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("LUMINUX").font(.metroOverline).tracking(1.5).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                Text("background")
                    .font(.metroTitle)
                    .padding(.leading, -3)
                    .padding(.bottom, 16)

                option(.favorites)
                option(.everything)

                Button {
                    if isLocked { openPro() } else { showsPhotoPicker = true }
                } label: {
                    row(title: "choose photos", detail: isChosenPhotos ? Self.name(for: settings.hubBackground, library: library, hubTiles: hubTiles) : "Pick the ones to rotate through", isSelected: isChosenPhotos, isLocked: isLocked)
                }
                .buttonStyle(TiltButtonStyle(touch: nil, size: .zero))

                if !library.albums.isEmpty {
                    header("albums")
                    ForEach(library.albums) { album in option(.album(album.id)) }
                }
                let sets = hubTiles.photoSets.values.sorted { $0.title < $1.title }
                if !sets.isEmpty {
                    header("photo sets")
                    ForEach(sets) { set in option(.photoSet(set.id)) }
                }
            }
            .padding(.horizontal, MetroMetrics.margin + 12)
            .padding(.vertical, 24)
        }
        .foregroundStyle(metro.foreground)
        .background(metro.background)
        .photosPicker(isPresented: $showsPhotoPicker, selection: $picked, maxSelectionCount: 50, matching: .images, photoLibrary: .shared())
        .onChange(of: picked) { _, items in
            // Only photos the app can read come back with an identifier.
            let ids = items.compactMap(\.itemIdentifier)
            guard !ids.isEmpty else { return }
            settings.hubBackground = .photos(ids)
            dismiss()
        }
    }

    private var isLocked: Bool { !store.unlocksPro }

    private var isChosenPhotos: Bool {
        if case .photos = Self.current(settings, store: store) { return true }
        return false
    }

    /// The source in use: without Pro, always favorites, so a choice made before a refund comes back with Pro.
    static func current(_ settings: AppSettings, store: ProStore) -> HubBackgroundSource {
        store.unlocksPro ? settings.hubBackground : .favorites
    }

    private func openPro() {
        dismiss()
        navigator.push(.pro)
    }

    private func option(_ source: HubBackgroundSource) -> some View {
        let locked = isLocked && source != .favorites
        return Button {
            if locked { return openPro() }
            settings.hubBackground = source
            dismiss()
        } label: {
            row(title: Self.name(for: source, library: library, hubTiles: hubTiles), detail: nil, isSelected: Self.current(settings, store: store) == source, isLocked: locked)
        }
        .buttonStyle(TiltButtonStyle(touch: nil, size: .zero))
    }

    private func row(title: String, detail: String?, isSelected: Bool, isLocked: Bool = false) -> some View {
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
                Text(detail).font(.metroCaption).foregroundStyle(metro.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.metro(20, .semilight))
            .foregroundStyle(metro.secondary)
            .padding(.top, 24)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
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
