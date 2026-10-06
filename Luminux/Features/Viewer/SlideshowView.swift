import Photos
import SwiftUI

/// Full-screen slideshow of the photos in a source: slow pan and zoom with cross-fades. Tap to stop.
struct SlideshowView: View {
    let source: AssetSource
    let startIndex: Int

    @Environment(PhotoLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position = 0
    @State private var photos: [Int] = []

    private static let slideDuration: Double = 5

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if photos.indices.contains(position) {
                let asset = library.assets(in: source).object(at: photos[position])
                KenBurnsSlide(asset: asset, seed: position, duration: Self.slideDuration + 1.5, animates: !reduceMotion)
                    .id(asset.localIdentifier)
                    .transition(.opacity.animation(.easeInOut(duration: 1.2)))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .accessibilityAction(named: "Stop slideshow") { dismiss() }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            photos = photoIndexes
            position = photos.firstIndex(where: { $0 >= startIndex }) ?? 0
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.slideDuration))
                guard !Task.isCancelled, !photos.isEmpty else { return }
                withAnimation { position = (position + 1) % photos.count }
            }
        }
    }

    /// Indexes of still photos in the source; videos are skipped.
    private var photoIndexes: [Int] {
        let assets = library.assets(in: source)
        return (0..<assets.count).filter { assets.object(at: $0).mediaType == .image }
    }
}

private struct KenBurnsSlide: View {
    let asset: PHAsset
    let seed: Int
    let duration: Double
    let animates: Bool

    @State private var image: UIImage?
    @State private var progress: CGFloat = 0
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        // Alternate pan direction and zoom so consecutive slides don't feel identical.
        let direction: CGFloat = seed.isMultiple(of: 2) ? 1 : -1
        let zoomIn = seed % 3 != 0

        GeometryReader { geo in
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    // Never below 1.08, so the pan never uncovers an edge.
                    .scaleEffect(zoomIn ? 1.08 + 0.12 * progress : 1.2 - 0.12 * progress)
                    .offset(x: direction * 18 * (progress - 0.5), y: -10 * (progress - 0.5))
                    .clipped()
            }
        }
        .ignoresSafeArea()
        .task(id: asset.renderKey) {
            let side = 1600 * displayScale
            for await next in ImageLoader.shared.images(for: asset, targetSize: CGSize(width: side, height: side)) {
                image = next
            }
        }
        .onAppear {
            guard animates else { return }
            withAnimation(.linear(duration: duration)) { progress = 1 }
        }
        .accessibilityElement()
        .accessibilityLabel(asset.spokenDescription)
    }
}
