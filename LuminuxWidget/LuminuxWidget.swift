import AppIntents
import SwiftUI
import WidgetKit

@main
struct LuminuxWidgets: WidgetBundle {
    var body: some Widget {
        PhotosLiveTile()
    }
}

enum TileSourceOption: String, AppEnum {
    case recent, favorites

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Photos"
    static let caseDisplayRepresentations: [TileSourceOption: DisplayRepresentation] = [
        .recent: "Recent",
        .favorites: "Favorites",
    ]

    var storeSource: LiveTileStore.Source { self == .recent ? .recent : .favorites }
}

struct TileConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Photos tile"
    static let description = IntentDescription("Cycles through your recent photos or your favorites.")

    @Parameter(title: "Show", default: .recent)
    var source: TileSourceOption
}

struct TileEntry: TimelineEntry {
    let date: Date
    let imageURLs: [URL]
    let accentHex: UInt32
    let title: String
}

struct TileProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TileEntry {
        TileEntry(date: .now, imageURLs: [], accentHex: LiveTileStore.accentHex, title: "photos")
    }

    func snapshot(for configuration: TileConfigurationIntent, in context: Context) async -> TileEntry {
        entry(for: configuration, at: .now, offset: 0)
    }

    /// Rotates which photo leads every 20 minutes, like a live tile flipping.
    func timeline(for configuration: TileConfigurationIntent, in context: Context) async -> Timeline<TileEntry> {
        let count = max(LiveTileStore.imageURLs(for: configuration.source.storeSource).count, 1)
        let entries = (0..<count).map { step in
            entry(for: configuration, at: .now.addingTimeInterval(Double(step) * 20 * 60), offset: step)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    private func entry(for configuration: TileConfigurationIntent, at date: Date, offset: Int) -> TileEntry {
        let urls = LiveTileStore.imageURLs(for: configuration.source.storeSource)
        let rotated = urls.isEmpty ? [] : Array(urls[(offset % urls.count)...] + urls[..<(offset % urls.count)])
        return TileEntry(
            date: date,
            imageURLs: rotated,
            accentHex: LiveTileStore.accentHex,
            title: configuration.source == .recent ? "photos" : "favorites"
        )
    }
}

struct PhotosLiveTile: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "PhotosLiveTile", intent: TileConfigurationIntent.self, provider: TileProvider()) { entry in
            TileView(entry: entry)
                .containerBackground(for: .widget) { Color(hex: entry.accentHex) }
                .widgetURL(URL(string: "luminux://hub"))
        }
        .configurationDisplayName("Photos")
        .description("A live tile of your recent photos or favorites.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct TileView: View {
    let entry: TileEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if entry.imageURLs.isEmpty {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 40, weight: .ultraLight))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                collage
            }
            Text(entry.title)
                .font(.custom("Selawik-Semilight", size: 15))
                .foregroundStyle(.white)
                .padding(12)
        }
    }

    @ViewBuilder
    private var collage: some View {
        let images = entry.imageURLs
        switch family {
        case .systemMedium:
            HStack(spacing: 4) {
                photo(images[0])
                VStack(spacing: 4) {
                    photo(images[safe: 1] ?? images[0])
                    photo(images[safe: 2] ?? images[0])
                }
            }
        case .systemLarge:
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                GridRow {
                    photo(images[0])
                    photo(images[safe: 1] ?? images[0])
                }
                GridRow {
                    photo(images[safe: 2] ?? images[0])
                    photo(images[safe: 3] ?? images[0])
                }
            }
        default:
            photo(images[0])
        }
    }

    private func photo(_ url: URL) -> some View {
        Color.clear
            .overlay {
                if let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
