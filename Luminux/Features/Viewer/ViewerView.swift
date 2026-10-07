import Photos
import SwiftUI

/// Full-screen photo and video viewer with swipe paging and the Metro app bar.
struct ViewerView: View {
    let request: ViewerRequest

    @Environment(PhotoLibrary.self) private var library
    @Environment(Navigator.self) private var navigator
    @Environment(\.metro) private var metro
    @Environment(\.dismiss) private var dismiss
    @Environment(ProStore.self) private var store
    @State private var index: Int?
    @State private var showsChrome = true
    @State private var isAppBarExpanded = false
    @State private var share: ShareItems?
    @State private var addToAlbum: AddToAlbumRequest?
    @State private var isZoomed = false
    @State private var editing: AssetItem?
    @State private var showsSlideshow = false
    @State private var showsPro = false
    @State private var dismissDrag: CGFloat = 0
    /// How much of the details panel is showing; the panel is open when this rests at `panelHeight`.
    @State private var detailsLift: CGFloat = 0
    @State private var showsDetails = false
    /// Stays true until the close animation finishes, so the panel can slide away.
    @State private var isPanelMounted = false
    @State private var screenHeight: CGFloat = 0
    @State private var playback = VideoPlayback()

    private var panelHeight: CGFloat { (screenHeight * 0.55).rounded() }
    private var chromeVisible: Bool { showsChrome && dismissDrag == 0 && !isPanelMounted }

    init(request: ViewerRequest) {
        self.request = request
        _index = State(initialValue: request.startIndex)
    }

    var body: some View {
        let assets = library.assets(in: request.source)
        let current = index.flatMap { assets.count > $0 ? assets.object(at: $0) : nil }

        ZStack(alignment: .topLeading) {
            Color.black
                .opacity(1 - min(dismissDrag / 500, 0.8))
                .ignoresSafeArea()

            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(0..<assets.count, id: \.self) { position in
                        ViewerPage(asset: assets.object(at: position), isCurrent: position == index, playback: playback) {
                            if showsDetails {
                                setDetails(open: false)
                            } else {
                                withAnimation(MetroMotion.fade) { showsChrome.toggle() }
                            }
                        } onZoomChange: { zoomed in
                            if position == index { isZoomed = zoomed }
                        }
                        .containerRelativeFrame([.horizontal, .vertical])
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $index)
            .scrollIndicators(.hidden)
            .ignoresSafeArea()
            .scaleEffect(1 - min(dismissDrag / 1600, 0.25))
            // Keeps the photo centred in the space left above the details panel.
            .offset(y: dismissDrag - min(detailsLift, panelHeight) / 2)
            .gesture(VerticalDragRecognizer(isEnabled: !isZoomed, onChange: verticalDragChanged, onEnd: verticalDragEnded))

            if chromeVisible, let current {
                Text(current.creationDate.map { $0.formatted(.dateTime.weekday(.wide).month(.wide).day().year().hour().minute()).lowercased() } ?? "")
                    .font(.metroCaption)
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, MetroMetrics.margin + 12)
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if isPanelMounted, let current {
                DetailsPanel(asset: current, onHeaderDrag: verticalDragChanged, onHeaderDragEnd: verticalDragEnded) {
                    setDetails(open: false)
                }
                .id(current.localIdentifier)
                .frame(height: max(panelHeight, detailsLift))
                .offset(y: max(panelHeight - detailsLift, 0))
                .environment(\.metro, MetroPalette(theme: .dark, accent: metro.accent))
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .overlay(alignment: .bottom) {
            if chromeVisible, let current {
                VStack(spacing: 0) {
                    if current.mediaType == .video {
                        VideoControlsRow(playback: playback)
                    }
                    MetroAppBar(buttons: buttons(for: current), menuItems: menu(for: current), isExpanded: $isAppBarExpanded)
                }
                .environment(\.metro, MetroPalette(theme: .dark, accent: metro.accent))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { screenHeight = $0 }
        .statusBarHidden(!showsChrome)
        // The zoom transition's own swipe-down would close the viewer instead of the panel.
        .interactiveDismissDisabled(isPanelMounted)
        .onChange(of: index) { _, newIndex in
            isZoomed = false
            if let newIndex, assets.count > newIndex {
                navigator.viewerCurrentID = assets.object(at: newIndex).localIdentifier
            }
        }
        .onChange(of: current?.localIdentifier, initial: true) {
            // The scroll position goes nil for a moment when the status bar hides; that isn't a page change.
            if let current { playback.load(current) }
        }
        .onDisappear { playback.load(nil) }
        // Like the original player, the controls get out of the way a moment after playback starts.
        .task(id: playback.isPlaying && showsChrome && !playback.isScrubbing) {
            guard playback.isPlaying, showsChrome else { return }
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, !isAppBarExpanded else { return }
            withAnimation(MetroMotion.fade) { showsChrome = false }
        }
        .onChange(of: library.changeToken) {
            // After a delete, stay at the same position or close when nothing is left.
            let count = library.assets(in: request.source).count
            if count == 0 {
                dismiss()
            } else if let index, index >= count {
                self.index = count - 1
            }
        }
        .assetActionSheets(share: $share, addToAlbum: $addToAlbum)
        .fullScreenCover(item: $editing) { item in EditorView(asset: item.asset) }
        .fullScreenCover(isPresented: $showsSlideshow) {
            SlideshowView(source: request.source, startIndex: index ?? 0)
        }
        .fullScreenCover(isPresented: $showsPro) {
            ProView { showsPro = false }
        }
    }

    /// Down past the start closes the viewer, up reveals details; with details open, the same drag moves the panel.
    private func verticalDragChanged(_ translation: CGFloat) {
        if showsDetails {
            detailsLift = rubberBand(panelHeight - translation)
        } else if translation > 0 {
            detailsLift = 0
            isPanelMounted = false
            dismissDrag = translation
        } else {
            dismissDrag = 0
            detailsLift = rubberBand(-translation)
            isPanelMounted = detailsLift > 0
        }
    }

    private func verticalDragEnded(_ translation: CGFloat, _ velocity: CGFloat) {
        if showsDetails {
            setDetails(open: !(translation > panelHeight * 0.3 || velocity > 700))
        } else if dismissDrag > 0 {
            if translation > 140 || velocity > 900 {
                dismiss()
            } else {
                withAnimation(MetroMotion.release) { dismissDrag = 0 }
            }
        } else {
            setDetails(open: -translation > 80 || velocity < -700)
        }
    }

    private func setDetails(open: Bool) {
        showsDetails = open
        isAppBarExpanded = false
        if open { isPanelMounted = true }
        withAnimation(MetroMotion.standard, completionCriteria: .logicallyComplete) {
            detailsLift = open ? panelHeight : 0
        } completion: {
            if !showsDetails { isPanelMounted = false }
        }
    }

    /// Follows the finger up to the panel height, then resists.
    private func rubberBand(_ lift: CGFloat) -> CGFloat {
        guard lift > panelHeight else { return max(lift, 0) }
        return panelHeight + (lift - panelHeight) * 0.2
    }

    private func buttons(for asset: PHAsset) -> [AppBarButton] {
        var buttons: [AppBarButton] = []
        if asset.mediaType == .video {
            buttons.append(AppBarButton(title: playback.isPlaying ? "pause" : "play", systemImage: playback.isPlaying ? "pause.fill" : "play.fill", isEnabled: playback.player != nil) {
                playback.togglePlay()
            })
        }
        buttons += [
            AppBarButton(title: "share", systemImage: "square.and.arrow.up") {
                Task {
                    let urls = await ImageLoader.shared.exportOriginals([asset])
                    if !urls.isEmpty { share = ShareItems(urls: urls) }
                }
            },
            AppBarButton(title: asset.isFavorite ? "unfavorite" : "favorite", systemImage: asset.isFavorite ? "heart.fill" : "heart") {
                Task { try? await library.setFavorite([asset], !asset.isFavorite) }
            },
        ]
        if asset.supportsLuminuxEdits {
            buttons.append(AppBarButton(title: "edit", systemImage: "crop.rotate") {
                withPro { editing = AssetItem(asset: asset) }
            })
        }
        buttons.append(AppBarButton(title: "delete", systemImage: "trash") {
            Task { try? await library.delete([asset]) }
        })
        return buttons
    }

    /// Runs a Pro feature, or shows what Pro adds when it isn't unlocked yet.
    private func withPro(_ action: () -> Void) {
        if store.isUnlocked {
            action()
        } else {
            showsPro = true
        }
    }

    private func menu(for asset: PHAsset) -> [AppBarMenuItem] {
        var items: [AppBarMenuItem] = []
        if asset.supportsLuminuxEdits {
            items.append(AppBarMenuItem(title: "rotate") {
                withPro { Task { try? await library.applyEdit(EditRecipe(quarterTurns: 1), to: asset) } }
            })
        }
        items.append(AppBarMenuItem(title: "add to album") { addToAlbum = AddToAlbumRequest(assets: [asset]) })
        items.append(AppBarMenuItem(title: "slideshow") { withPro { showsSlideshow = true } })
        items.append(AppBarMenuItem(title: "details") { setDetails(open: true) })
        if asset.hasAdjustments && asset.canPerform(.content) {
            items.append(AppBarMenuItem(title: "revert to original") {
                Task { try? await library.revertEdits(asset) }
            })
        }
        return items
    }
}

private struct ViewerPage: View {
    let asset: PHAsset
    let isCurrent: Bool
    let playback: VideoPlayback
    let onTap: () -> Void
    let onZoomChange: (Bool) -> Void

    @Environment(AppSettings.self) private var settings

    var body: some View {
        switch asset.mediaType {
        case .video:
            VideoPage(asset: asset, isCurrent: isCurrent, playback: playback, onTap: onTap)
        default:
            if asset.mediaSubtypes.contains(.photoLive) && settings.playsLivingImages {
                LivePhotoPage(asset: asset, isCurrent: isCurrent, onTap: onTap)
            } else {
                PhotoPage(asset: asset, isCurrent: isCurrent, onTap: onTap, onZoomChange: onZoomChange)
            }
        }
    }
}

private struct PhotoPage: View {
    let asset: PHAsset
    let isCurrent: Bool
    let onTap: () -> Void
    let onZoomChange: (Bool) -> Void

    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZoomableImageView(image: image, isCurrent: isCurrent, onSingleTap: onTap, onZoomChange: onZoomChange)
            .task(id: asset.renderKey) {
                // Screen-sized first; zooming in shows the same pixels, which is enough for v1.
                let side = 1400 * displayScale
                for await next in ImageLoader.shared.images(for: asset, targetSize: CGSize(width: side, height: side), contentMode: .aspectFit) {
                    image = next
                }
            }
            .accessibilityElement()
            .accessibilityLabel(asset.spokenDescription)
            .accessibilityAddTraits(.isImage)
    }
}

private struct LivePhotoPage: View {
    let asset: PHAsset
    let isCurrent: Bool
    let onTap: () -> Void

    @State private var livePhoto: PHLivePhoto?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        LivePhotoView(livePhoto: isCurrent ? livePhoto : nil, playsOnShow: isCurrent)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .task(id: asset.renderKey) {
                let side = 1400 * displayScale
                for await next in ImageLoader.shared.livePhoto(for: asset, targetSize: CGSize(width: side, height: side)) {
                    livePhoto = next
                }
            }
            .accessibilityElement()
            .accessibilityLabel(asset.spokenDescription)
            .accessibilityAddTraits(.isImage)
    }
}

private struct VideoPage: View {
    let asset: PHAsset
    let isCurrent: Bool
    let playback: VideoPlayback
    let onTap: () -> Void

    @State private var poster: UIImage?
    @Environment(\.displayScale) private var displayScale

    private var isLoaded: Bool { isCurrent && playback.assetID == asset.localIdentifier && playback.player != nil }

    var body: some View {
        ZStack {
            Color.black
            if let poster {
                Image(uiImage: poster).resizable().scaledToFit()
            }
            // The layer stays clear until its first frame, so the poster shows through while loading.
            if isLoaded {
                PlayerLayerView(player: playback.player)
            }
            if !(isLoaded && playback.isPlaying) {
                Button {
                    playback.togglePlay()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.white)
                        .frame(width: 76, height: 76)
                        .background(Circle().fill(.black.opacity(0.35)).strokeBorder(.white, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .disabled(!isLoaded)
                .opacity(isLoaded ? 1 : 0.5)
                .accessibilityLabel("Play")
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .animation(MetroMotion.fade, value: playback.isPlaying)
        .task(id: asset.renderKey) {
            let side = 1400 * displayScale
            for await next in ImageLoader.shared.images(for: asset, targetSize: CGSize(width: side, height: side), contentMode: .aspectFit) {
                poster = next
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(asset.spokenDescription)
    }
}
