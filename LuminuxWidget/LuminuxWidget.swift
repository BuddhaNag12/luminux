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
    case recent, favorites, collection

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Photos"
    static let caseDisplayRepresentations: [TileSourceOption: DisplayRepresentation] = [
        .recent: "Recent",
        .favorites: "Favorites",
        .collection: "A collection",
    ]
}

/// An album or photo set made into a widget from the app ("make a widget" in its menu).
struct TileCollectionEntity: AppEntity {
    let id: String
    let title: String

    init(_ collection: LiveTileStore.Collection) {
        id = collection.id
        title = collection.title
    }

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Collection"
    static let defaultQuery = TileCollectionQuery()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct TileCollectionQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [TileCollectionEntity] {
        LiveTileStore.collections.filter { identifiers.contains($0.id) }.map(TileCollectionEntity.init)
    }

    func suggestedEntities() async throws -> [TileCollectionEntity] {
        LiveTileStore.collections.map(TileCollectionEntity.init)
    }
}

struct TileConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Photos tile"
    static let description = IntentDescription("Cycles through your recent photos, your favorites or a collection you made a widget from in Luminux.")

    @Parameter(title: "Show", default: .recent)
    var source: TileSourceOption

    @Parameter(title: "Collection")
    var collection: TileCollectionEntity?

    static var parameterSummary: some ParameterSummary {
        When(\.$source, .equalTo, .collection) {
            Summary { \.$source; \.$collection }
        } otherwise: {
            Summary { \.$source }
        }
    }

    /// The collection as the app last saved it, so a rename shows up without editing the widget.
    var storedCollection: LiveTileStore.Collection? {
        guard source == .collection, let id = collection?.id else { return nil }
        return LiveTileStore.collections.first { $0.id == id }
    }

    var imageURLs: [URL] {
        switch source {
        case .recent: LiveTileStore.imageURLs(for: .recent)
        case .favorites: LiveTileStore.imageURLs(for: .favorites)
        case .collection: storedCollection.map(LiveTileStore.imageURLs(for:)) ?? []
        }
    }

    var tileTitle: String {
        switch source {
        case .recent: "photos"
        case .favorites: "favorites"
        case .collection: storedCollection?.title.lowercased() ?? "collection"
        }
    }

    /// Opens what the tile shows: the album or photo set, or the hub.
    var url: URL? {
        guard let id = storedCollection?.id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return URL(string: "luminux://hub")
        }
        return URL(string: "luminux://collection?id=\(id)")
    }
}

struct TileEntry: TimelineEntry {
    let date: Date
    let imageURLs: [URL]
    let accentHex: UInt32
    let title: String
    let isPro: Bool
    var url: URL? = URL(string: "luminux://hub")
    /// "A collection" is picked but none is chosen yet, or it was removed in the app.
    var needsCollection = false
}

struct TileProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TileEntry {
        TileEntry(date: .now, imageURLs: [], accentHex: LiveTileStore.accentHex, title: "photos", isPro: true)
    }

    func snapshot(for configuration: TileConfigurationIntent, in context: Context) async -> TileEntry {
        entry(for: configuration, at: .now, order: configuration.imageURLs)
    }

    /// Shuffles the photos every few seconds, like the hub's live tiles. WidgetKit draws each entry ahead of time and
    /// limits how often a widget can ask for a new timeline each day.
    /// shortcut: 5-second entries are an experiment; if iOS skips them, blanks the tile or stops after its daily
    /// reload budget, go back to minutes.
    func timeline(for configuration: TileConfigurationIntent, in context: Context) async -> Timeline<TileEntry> {
        let urls = configuration.imageURLs
        guard urls.count > 1 else {
            return Timeline(entries: [entry(for: configuration, at: .now, order: urls)], policy: .after(.now.addingTimeInterval(3600)))
        }
        var entries: [TileEntry] = []
        var date = Date.now
        var order = urls.shuffled()
        while entries.count < Self.entriesPerTimeline {
            entries.append(entry(for: configuration, at: date, order: order))
            date = date.addingTimeInterval(Self.shuffleInterval)
            order = Self.reshuffled(order)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    static let shuffleInterval: TimeInterval = 5
    /// Ten minutes of shuffling per timeline.
    static let entriesPerTimeline = 120

    /// A new random order that never leads with the photo that's showing now.
    static func reshuffled(_ order: [URL]) -> [URL] {
        guard order.count > 1 else { return order }
        var next = order.shuffled()
        while next.first == order.first { next.shuffle() }
        return next
    }

    private func entry(for configuration: TileConfigurationIntent, at date: Date, order: [URL]) -> TileEntry {
        TileEntry(
            date: date,
            imageURLs: order,
            accentHex: LiveTileStore.accentHex,
            title: configuration.tileTitle,
            isPro: LiveTileStore.isPro,
            url: configuration.url,
            needsCollection: configuration.source == .collection && configuration.storedCollection == nil
        )
    }
}

struct PhotosLiveTile: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "PhotosLiveTile", intent: TileConfigurationIntent.self, provider: TileProvider()) { entry in
            TileView(entry: entry)
                .containerBackground(for: .widget) { Color(hex: entry.accentHex) }
        }
        .configurationDisplayName("Photos")
        .description("A live tile of your recent photos, favorites or a collection from Luminux.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct TileView: View {
    let entry: TileEntry
    @Environment(\.widgetFamily) private var family

    /// The medium and large tiles come with Luminux Pro; the small one is free.
    private var isLocked: Bool { family != .systemSmall && !entry.isPro }

    var body: some View {
        if isLocked {
            lockedFace.widgetURL(URL(string: "luminux://pro"))
        } else {
            tile.widgetURL(entry.url)
        }
    }

    private var lockedFace: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "lock")
                .font(.system(size: 22, weight: .light))
            Spacer()
            Text("Wide tiles come with Luminux Pro. Tap to see what it adds.")
                .font(.custom("Selawik-Semilight", size: 15))
            Text("photos")
                .font(.custom("Selawik-Semilight", size: 15))
                .opacity(0.7)
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var tile: some View {
        ZStack(alignment: .bottomLeading) {
            if entry.needsCollection {
                Text("Touch and hold, then Edit Widget to choose a collection.")
                    .font(.custom("Selawik-Semilight", size: 15))
                    .foregroundStyle(.white)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if entry.imageURLs.isEmpty {
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

    /// Each photo slides up into place when the tile shuffles, like the hub's live tiles.
    private func photo(_ url: URL) -> some View {
        Color.clear
            .overlay {
                if let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image).resizable()
                        // A tinted or clear Home Screen otherwise draws photos as flat white shapes.
                        .widgetAccentedRenderingMode(.fullColor)
                        .scaledToFill()
                        .id(url)
                        .transition(.push(from: .bottom))
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
