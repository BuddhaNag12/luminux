import AVFoundation
import ImageIO
import MapKit
import Photos
import SwiftUI

/// Photo info that slides up under the viewer: when, what file, how big, which camera settings, and where.
/// Dragging the header, or pulling the list down past its top, hands the drag back to the viewer.
struct DetailsPanel: View {
    let asset: PHAsset
    var onHeaderDrag: (_ translation: CGFloat) -> Void
    var onHeaderDragEnd: (_ translation: CGFloat, _ velocity: CGFloat) -> Void
    var onClose: () -> Void

    @Environment(\.metro) private var metro
    @State private var details: AssetDetails?
    @State private var pullDown: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Capsule()
                    .fill(metro.secondary.opacity(0.5))
                    .frame(width: 36, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                Text("details")
                    .font(.metroPivot)
                    .padding(.leading, -2)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, MetroMetrics.margin + 12)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { onHeaderDrag($0.translation.height) }
                    .onEnded { onHeaderDragEnd($0.translation.height, $0.velocity.height) }
            )
            .accessibilityAddTraits(.isHeader)

            ScrollView {
                rows
                    .padding(.horizontal, MetroMetrics.margin + 12)
                    .padding(.bottom, 40)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                -(geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, overscroll in
                pullDown = overscroll
            }
            .onScrollPhaseChange { old, _ in
                if old == .interacting, pullDown > 60 { onClose() }
            }
        }
        .foregroundStyle(metro.foreground)
        .background(metro.chrome)
        .accessibilityAction(.escape, onClose)
        .task(id: asset.renderKey) { details = await AssetDetails.load(for: asset) }
    }

    @ViewBuilder private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let details {
                ForEach(details.rows, id: \.label) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.label).font(.metro(15, .semilight)).foregroundStyle(metro.secondary)
                        Text(row.value).font(.metroBody).textSelection(.enabled)
                    }
                    .padding(.bottom, 16)
                    .accessibilityElement(children: .combine)
                }

                if let location = asset.location {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: location.coordinate,
                        latitudinalMeters: 2000,
                        longitudinalMeters: 2000
                    ))) {
                        Marker("", coordinate: location.coordinate).tint(metro.accentColor)
                    }
                    .frame(height: 200)
                    .allowsHitTesting(false)
                    .accessibilityLabel("Map of where this was taken")
                }
            } else {
                ProgressView().tint(metro.accentColor).padding(.top, 8)
            }
        }
    }
}

struct AssetDetails {
    struct Row {
        let label: String
        let value: String
    }

    var rows: [Row]

    static func load(for asset: PHAsset) async -> AssetDetails {
        var rows: [Row] = []
        if let date = asset.creationDate {
            rows.append(Row(label: "taken", value: date.formatted(date: .complete, time: .shortened)))
        }

        let resource = PHAssetResource.assetResources(for: asset).first
        if let name = resource?.originalFilename {
            rows.append(Row(label: "file name", value: name))
        }

        let megapixels = Double(asset.pixelWidth * asset.pixelHeight) / 1_000_000
        rows.append(Row(label: "dimensions", value: "\(asset.pixelWidth) × \(asset.pixelHeight) · \(megapixels.formatted(.number.precision(.fractionLength(1)))) MP"))

        // Photos read their original for the camera info anyway, so its length is the size.
        let original = asset.mediaType == .image ? await originalImageData(for: asset) : nil
        let bytes = asset.mediaType == .video ? await videoFileSize(for: asset) : original?.count
        if let bytes {
            rows.append(Row(label: "size", value: ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)))
        }

        switch asset.mediaType {
        case .video:
            rows.append(Row(label: "type", value: "video · \(Duration.seconds(asset.duration).formatted(.time(pattern: .minuteSecond)))"))
        default:
            rows.append(Row(label: "type", value: asset.mediaSubtypes.contains(.photoLive) ? "live photo" : "photo"))
        }

        if let original, let exif = cameraInfo(from: original) {
            rows.append(contentsOf: exif)
        }

        if let coordinate = asset.location?.coordinate {
            rows.append(Row(label: "location", value: "\(coordinate.latitude.formatted(.number.precision(.fractionLength(5)))), \(coordinate.longitude.formatted(.number.precision(.fractionLength(5))))"))
        }
        if asset.hasAdjustments {
            rows.append(Row(label: "edited", value: "yes · revert from the ••• menu"))
        }
        return AssetDetails(rows: rows)
    }

    private static func originalImageData(for asset: PHAsset) async -> Data? {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.version = .original
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { @Sendable data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }

    /// The size of a video that's on the device; nil for one that's only in iCloud, rather than downloading it.
    private static func videoFileSize(for asset: PHAsset) async -> Int? {
        let options = PHVideoRequestOptions()
        options.version = .original
        options.isNetworkAccessAllowed = false
        let url: URL? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { @Sendable video, _, _ in
                continuation.resume(returning: (video as? AVURLAsset)?.url)
            }
        }
        return url.flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
    }

    private static func cameraInfo(from data: Data) -> [Row]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }

        var rows: [Row] = []
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let camera = [tiff?[kCGImagePropertyTIFFMake] as? String, tiff?[kCGImagePropertyTIFFModel] as? String]
            .compactMap { $0 }
            .joined(separator: " ")
        if !camera.isEmpty {
            rows.append(Row(label: "camera", value: camera))
        }

        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            var parts: [String] = []
            if let aperture = exif[kCGImagePropertyExifFNumber] as? Double {
                parts.append("f/\(aperture.formatted(.number.precision(.fractionLength(0...1))))")
            }
            if let exposure = exif[kCGImagePropertyExifExposureTime] as? Double, exposure > 0 {
                parts.append(exposure >= 1 ? "\(exposure.formatted()) s" : "1/\(Int((1 / exposure).rounded())) s")
            }
            if let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first {
                parts.append("ISO \(iso)")
            }
            if let focal = exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? Int {
                parts.append("\(focal) mm")
            }
            if !parts.isEmpty {
                rows.append(Row(label: "exposure", value: parts.joined(separator: " · ")))
            }
        }
        return rows
    }
}
