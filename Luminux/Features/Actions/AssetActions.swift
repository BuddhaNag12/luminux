import Photos
import SwiftUI
import UIKit

struct ShareItems: Identifiable {
    let id = UUID()
    let urls: [URL]
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct AddToAlbumRequest: Identifiable {
    let id = UUID()
    let assets: [PHAsset]
}

/// Metro-style album picker; "new album" asks for a name and adds the photos to it.
struct AddToAlbumSheet: View {
    let request: AddToAlbumRequest

    @Environment(PhotoLibrary.self) private var library
    @Environment(\.metro) private var metro
    @Environment(\.dismiss) private var dismiss
    @State private var isNaming = false
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LUMINUX").font(.metroOverline).tracking(1.5)
            Text("add to album")
                .font(.metroTitle)
                .lineLimit(1)
                .fixedSize()
                .padding(.leading, -3)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Button {
                        isNaming = true
                    } label: {
                        HStack(spacing: 16) {
                            metro.accentColor
                                .frame(width: 64, height: 64)
                                .overlay { Image(systemName: "plus").font(.system(size: 26, weight: .light)).foregroundStyle(.white) }
                            Text("new album").font(.metro(22, .semilight))
                        }
                    }
                    .buttonStyle(TiltButtonStyle(touch: nil, size: .zero))

                    ForEach(library.albums.filter(\.isUserAlbum)) { album in
                        Button {
                            Task {
                                try? await library.add(request.assets, toAlbum: album.id)
                                dismiss()
                            }
                        } label: {
                            AlbumRow(album: album)
                        }
                        .buttonStyle(TiltButtonStyle(touch: nil, size: .zero))
                    }
                }
                .padding(.top, 16)
            }
        }
        .foregroundStyle(metro.foreground)
        .padding(.horizontal, MetroMetrics.margin + 12)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(metro.background)
        .alert("New album", isPresented: $isNaming) {
            TextField("Album name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                Task {
                    try? await library.createAlbum(named: name, with: request.assets)
                    dismiss()
                }
            }
        }
    }
}

struct AlbumRow: View {
    let album: Album
    @Environment(PhotoLibrary.self) private var library
    @Environment(\.metro) private var metro
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        HStack(spacing: 16) {
            Group {
                if let id = album.keyAssetID, let asset = library.asset(id: id) {
                    AssetThumbnail(asset: asset, pixelSide: 64 * displayScale)
                } else {
                    metro.chrome
                }
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 2) {
                Text(album.title).font(.metro(22, .semilight)).lineLimit(1)
                Text("\(album.count)").font(.metroCaption).foregroundStyle(metro.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// App bar buttons shared by every screen that has a select mode.
@MainActor
enum SelectionActions {
    static func buttons(
        selection: SelectionModel,
        library: PhotoLibrary,
        share: @escaping ([PHAsset]) -> Void,
        addToAlbum: @escaping ([PHAsset]) -> Void
    ) -> [AppBarButton] {
        let hasSelection = !selection.selectedIDs.isEmpty
        return [
            AppBarButton(title: "share", systemImage: "square.and.arrow.up", isEnabled: hasSelection) {
                share(selection.selectedAssets)
            },
            AppBarButton(title: "favorite", systemImage: "heart", isEnabled: hasSelection) {
                let assets = selection.selectedAssets
                Task {
                    try? await library.setFavorite(assets, true)
                    selection.end()
                }
            },
            AppBarButton(title: "add", systemImage: "plus", isEnabled: hasSelection) {
                addToAlbum(selection.selectedAssets)
            },
            AppBarButton(title: "delete", systemImage: "trash", isEnabled: hasSelection) {
                let assets = selection.selectedAssets
                Task {
                    try? await library.delete(assets)
                    selection.end()
                }
            },
        ]
    }
}

extension View {
    /// Share sheet and add-to-album sheet driven by optional state.
    func assetActionSheets(share: Binding<ShareItems?>, addToAlbum: Binding<AddToAlbumRequest?>) -> some View {
        sheet(item: share) { items in
            ActivityView(items: items.urls)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: addToAlbum) { request in
            AddToAlbumSheet(request: request)
        }
    }
}
