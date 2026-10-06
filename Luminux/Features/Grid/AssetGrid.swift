import Photos
import SwiftUI

@Observable
final class SelectionModel {
    var isActive = false
    var selectedIDs: Set<String> = []

    func toggle(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func begin(with id: String? = nil) {
        selectedIDs = id.map { [$0] } ?? []
        withAnimation(MetroMotion.standard) { isActive = true }
    }

    /// Selects every id, or clears them all when every one is already selected.
    func toggleAll(_ ids: [String]) {
        if ids.allSatisfy(selectedIDs.contains) {
            selectedIDs.subtract(ids)
        } else {
            selectedIDs.formUnion(ids)
        }
    }

    func end() {
        withAnimation(MetroMotion.standard) { isActive = false }
        selectedIDs = []
    }

    var selectedAssets: [PHAsset] {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: Array(selectedIDs), options: nil)
        return result.objects(at: IndexSet(integersIn: 0..<result.count))
    }
}

/// Square photo grid, optionally grouped under month headers that open the jump list.
struct AssetGrid: View {
    let source: AssetSource
    var sections: [MonthSection]?
    var columns = 4
    var selection: SelectionModel
    var emptyMessage = "Nothing here yet."
    var onHeaderTap: (() -> Void)?
    @Binding var jumpTarget: String?

    @Environment(PhotoLibrary.self) private var library
    @Environment(Navigator.self) private var navigator
    @Environment(\.metro) private var metro
    @Environment(\.displayScale) private var displayScale
    @State private var tileSide: CGFloat = 90
    /// The tile a long press just selected, so the tap that ends the press doesn't toggle it straight back off.
    @State private var longPressedID: String?
    @State private var featherOrigin = FeatherRowOrigin()

    var body: some View {
        let assets = library.assets(in: source)
        let gridItems = Array(repeating: GridItem(.flexible(), spacing: MetroMetrics.gutter), count: columns)

        ScrollViewReader { proxy in
            ScrollView {
                if assets.count == 0 && library.isLoaded {
                    Text(emptyMessage)
                        .font(.metroBody)
                        .foregroundStyle(metro.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                        .metroFeather(row: 0)
                }

                LazyVGrid(columns: gridItems, alignment: .leading, spacing: MetroMetrics.gutter) {
                    if let sections {
                        let headerRows = Self.headerRows(for: sections, columns: columns)
                        ForEach(Array(sections.enumerated()), id: \.element.id) { position, section in
                            Section {
                                tiles(assets, range: section.range, firstRow: headerRows[position] + 1)
                            } header: {
                                header(section, assets: assets)
                                    .metroFeather(row: headerRows[position])
                            }
                        }
                    } else {
                        tiles(assets, range: 0..<assets.count, firstRow: 0)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                    tileSide = (width - MetroMetrics.gutter * CGFloat(columns - 1)) / CGFloat(columns)
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .environment(\.featherRowOrigin, featherOrigin)
            .onScrollGeometryChange(for: Int.self) { geometry in
                Int(max(geometry.contentOffset.y + geometry.contentInsets.top, 0) / (tileSide + MetroMetrics.gutter))
            } action: { _, row in
                featherOrigin.row = row
            }
            .sensoryFeedback(.selection, trigger: longPressedID) { _, new in new != nil }
            .onChange(of: jumpTarget) { _, target in
                guard let target else { return }
                proxy.scrollTo(target, anchor: .top)
                jumpTarget = nil
            }
        }
        .padding(.horizontal, MetroMetrics.margin)
    }

    /// The stagger row of each month header; its photos take the rows after it.
    private static func headerRows(for sections: [MonthSection], columns: Int) -> [Int] {
        var rows: [Int] = []
        var next = 0
        for section in sections {
            rows.append(next)
            next += 1 + (section.count + columns - 1) / columns
        }
        return rows
    }

    private func tiles(_ assets: PHFetchResult<PHAsset>, range: Range<Int>, firstRow: Int) -> some View {
        ForEach(range.clamped(to: 0..<assets.count), id: \.self) { index in
            let asset = assets.object(at: index)
            let id = asset.localIdentifier
            Button {
                if longPressedID == id {
                    longPressedID = nil
                } else if selection.isActive {
                    selection.toggle(id)
                } else {
                    navigator.openViewer(source, at: id, index: index)
                }
            } label: {
                AssetThumbnail(asset: asset, pixelSide: tileSide * displayScale)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(alignment: .topTrailing) {
                        if selection.isActive {
                            SelectionBox(isSelected: selection.selectedIDs.contains(id))
                                .padding(6)
                                .transition(.opacity)
                        }
                    }
                    .overlay {
                        if selection.selectedIDs.contains(id) {
                            Rectangle().strokeBorder(metro.accentColor, lineWidth: 3)
                        }
                    }
            }
            .buttonStyle(TiltButtonStyle(touch: nil, size: .zero))
            .metroFeather(row: firstRow + (index - range.lowerBound) / columns, column: (index - range.lowerBound) % columns)
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                guard !selection.isActive else { return }
                longPressedID = id
                selection.begin(with: id)
            })
            .zoomSource(id: id)
            .accessibilityAddTraits(selection.selectedIDs.contains(id) ? .isSelected : [])
        }
    }

    private func header(_ section: MonthSection, assets: PHFetchResult<PHAsset>) -> some View {
        HStack(spacing: 0) {
            Button {
                onHeaderTap?()
            } label: {
                Text(section.title())
                    .font(.metro(20, .semilight))
                    .foregroundStyle(metro.accentColor)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onHeaderTap == nil)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHint(onHeaderTap == nil ? "" : "Shows all months")

            if selection.isActive {
                let ids = section.range.clamped(to: 0..<assets.count).map { assets.object(at: $0).localIdentifier }
                let selectedCount = ids.count { selection.selectedIDs.contains($0) }
                Button {
                    selection.toggleAll(ids)
                } label: {
                    SelectionBox(isSelected: selectedCount == ids.count, isMixed: selectedCount > 0 && selectedCount < ids.count)
                        .frame(width: 44, height: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
                .transition(.opacity)
                .accessibilityLabel(selectedCount == ids.count ? "Clear \(section.title())" : "Select all of \(section.title())")
            }
        }
        .id(section.id)
    }
}

struct SelectionBox: View {
    let isSelected: Bool
    /// Some but not all of a group is selected.
    var isMixed = false
    @Environment(\.metro) private var metro

    var body: some View {
        let isFilled = isSelected || isMixed
        Rectangle()
            .fill(isFilled ? metro.accentColor : .black.opacity(0.25))
            .strokeBorder(isFilled ? metro.accentColor : .white, lineWidth: 2)
            .frame(width: 24, height: 24)
            .overlay {
                if isFilled {
                    Image(systemName: isSelected ? "checkmark" : "minus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
    }
}

struct AssetThumbnail: View {
    let asset: PHAsset
    var pixelSide: CGFloat

    @State private var image: UIImage?
    @Environment(\.metro) private var metro

    var body: some View {
        metro.chrome
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            // Clipping doesn't limit hit testing; without this, an overflowing photo steals taps from its neighbours.
            .contentShape(Rectangle())
            .overlay(alignment: .bottomTrailing) {
                if asset.mediaType == .video {
                    Text(Duration.seconds(asset.duration).formatted(.time(pattern: .minuteSecond)))
                        .font(.metro(12, .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .background(.black.opacity(0.6))
                        .padding(4)
                }
            }
            .overlay(alignment: .topLeading) {
                if asset.mediaSubtypes.contains(.photoLive) {
                    Image(systemName: "livephoto")
                        .font(.system(size: 12, weight: .light))
                        .foregroundStyle(.white)
                        .padding(5)
                }
            }
            .task(id: asset.renderKey) {
                let side = max(pixelSide, 60)
                for await next in ImageLoader.shared.images(for: asset, targetSize: CGSize(width: side, height: side)) {
                    image = next
                }
            }
            .accessibilityElement()
            .accessibilityLabel(asset.spokenDescription)
    }
}

extension PHAsset {
    /// Changes when the photo is edited, so image loads keyed on it refresh.
    var renderKey: String {
        "\(localIdentifier)-\(modificationDate?.timeIntervalSinceReferenceDate ?? 0)"
    }

    var spokenDescription: String {
        let kind = mediaType == .video ? "Video" : (mediaSubtypes.contains(.photoLive) ? "Live Photo" : "Photo")
        guard let creationDate else { return kind }
        return "\(kind), \(creationDate.formatted(date: .long, time: .shortened))"
    }
}
