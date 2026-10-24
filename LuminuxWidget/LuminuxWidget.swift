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

/// How the tile changes its photos, after the live tiles on the hub and Windows Phone's Photos tile.
enum TileStyle: String, AppEnum {
    case shuffle, mosaic, flip, peek

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Style"
    static let caseDisplayRepresentations: [TileStyle: DisplayRepresentation] = [
        .shuffle: "Shuffle",
        .mosaic: "Mosaic",
        .flip: "Flip",
        .peek: "Peek",
    ]
}

/// The tile's shuffle button. WidgetKit asks for a new timeline once it has run, and every timeline starts from a
/// fresh shuffle, so there's nothing for it to do itself.
struct ShuffleTileIntent: AppIntent {
    static let title: LocalizedStringResource = "Shuffle photos"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult { .result() }
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

    @Parameter(title: "Style", default: .shuffle)
    var style: TileStyle

    static var parameterSummary: some ParameterSummary {
        When(\.$source, .equalTo, .collection) {
            Summary { \.$source; \.$collection; \.$style }
        } otherwise: {
            Summary { \.$source; \.$style }
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
    var date: Date
    /// What each photo slot shows, in slot order.
    let imageURLs: [URL]
    /// The side the changed photo slides in from.
    var side: TileShuffle.Side = .bottom
    var generations: [Int] = []
    /// The slot that just changed; the small Home Screen tile shows only that one.
    var changed: Int?
    let accentHex: UInt32
    let title: String
    let isPro: Bool
    var url: URL? = URL(string: "luminux://hub")
    /// "A collection" is picked but none is chosen yet, or it was removed in the app.
    var needsCollection = false
    /// Pro and switched on in settings; otherwise StandBy shows the plain one-photo tile.
    var showsStandBy = false
    var style: TileStyle = .shuffle
    /// A peek step: the photos slide up to show what the tile is.
    var isPeeking = false
}

struct TileProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TileEntry {
        TileEntry(date: .now, imageURLs: [], accentHex: LiveTileStore.accentHex, title: "photos", isPro: true)
    }

    func snapshot(for configuration: TileConfigurationIntent, in context: Context) async -> TileEntry {
        entry(for: configuration, at: .now, order: Array(configuration.imageURLs.prefix(Self.slots(for: context.family, style: configuration.style))))
    }

    /// How many photos each size shows. The small tile keeps three for its StandBy face, which WidgetKit doesn't tell
    /// the timeline about; on the Home Screen it shows whichever changed last.
    static func slots(for family: WidgetFamily, style: TileStyle) -> Int {
        if family.isAccessory { return 1 }
        if style == .mosaic {
            let mosaic = mosaic(for: family)
            return mosaic.columns * mosaic.rows
        }
        return family == .systemSmall || family == .systemMedium ? 3 : 4
    }

    /// The mosaic's grid: small, roughly square cells, and no more of them than the photos the app exports.
    static func mosaic(for family: WidgetFamily) -> (columns: Int, rows: Int) {
        if #available(iOS 27, *), family == .systemExtraLargePortrait { return (3, 4) }
        return switch family {
        case .systemMedium: (4, 2)
        case .systemExtraLarge: (4, 3)
        default: (3, 3)
        }
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
        let isPeek = configuration.style == .peek
        // A peek after every third change: three quarters of the entries change a photo.
        let count = isPeek ? Self.entriesPerTimeline * 3 / 4 : Self.entriesPerTimeline
        let steps = TileShuffle.steps(pool: urls, slots: Self.slots(for: context.family, style: configuration.style), count: count)
        var entries = steps.map { step in
            var entry = entry(for: configuration, at: .now, order: step.slots)
            entry.side = step.side
            entry.generations = step.generations
            entry.changed = step.changed
            return entry
        }
        if isPeek { entries = TileShuffle.withPeeks(entries, every: 3) { $0.isPeeking = true } }
        for index in entries.indices {
            entries[index].date = .now.addingTimeInterval(Double(index) * Self.shuffleInterval)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    static let shuffleInterval: TimeInterval = 5
    /// Ten minutes of shuffling per timeline.
    static let entriesPerTimeline = 120

    private func entry(for configuration: TileConfigurationIntent, at date: Date, order: [URL]) -> TileEntry {
        TileEntry(
            date: date,
            imageURLs: order,
            accentHex: LiveTileStore.accentHex,
            title: configuration.tileTitle,
            isPro: LiveTileStore.unlocksWideTiles,
            url: configuration.url,
            needsCollection: configuration.source == .collection && configuration.storedCollection == nil,
            showsStandBy: LiveTileStore.showsStandBy && LiveTileStore.unlocksWideTiles,
            style: configuration.style
        )
    }
}

struct PhotosLiveTile: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "PhotosLiveTile", intent: TileConfigurationIntent.self, provider: TileProvider()) { entry in
            TileView(entry: entry)
        }
        .configurationDisplayName("Photos")
        .description("A live tile of your recent photos, favorites or a collection from Luminux.")
        .supportedFamilies(Self.families)
        .contentMarginsDisabled()
    }

    private static var families: [WidgetFamily] {
        var families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline]
        // iPhone Duo's open screen.
        if #available(iOS 27, *) { families += [.systemExtraLarge, .systemExtraLargePortrait] }
        return families
    }
}

extension WidgetFamily {
    /// The Lock Screen's sizes.
    var isAccessory: Bool { [.accessoryCircular, .accessoryRectangular, .accessoryInline].contains(self) }
}

struct TileView: View {
    let entry: TileEntry
    @Environment(\.widgetFamily) private var family
    /// False in StandBy (the phone charging on its side), where the small tile becomes photo tiles and a date tile.
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    /// Accented on a tinted or clear Home Screen, vibrant on the Lock Screen.
    @Environment(\.widgetRenderingMode) private var renderingMode

    /// The medium and larger tiles come with Luminux Pro; the small one and the Lock Screen's are free.
    private var isLocked: Bool { family != .systemSmall && !family.isAccessory && !entry.isPro }

    /// Photos sit on near-black, so the gaps between them read as a dark frame rather than lines of accent colour;
    /// the accent stays behind the lock and empty faces.
    private var showsPhotos: Bool { !isLocked && !entry.needsCollection && !entry.imageURLs.isEmpty }

    /// Text on the accent: black on the light accents, white on the rest.
    private var onAccent: Color { AccentContrast.needsDarkText(entry.accentHex) ? .black : .white }

    var body: some View {
        Group {
            if family.isAccessory {
                accessory.widgetURL(entry.url)
            } else if isLocked {
                lockedFace.widgetURL(URL(string: "luminux://hub"))
            } else {
                tile.widgetURL(entry.url)
            }
        }
        .containerBackground(for: .widget) {
            if family.isAccessory {
                Color.clear
            } else {
                showsPhotos ? Color(hex: 0x0B0B0B) : Color(hex: entry.accentHex)
            }
        }
    }

    @ViewBuilder
    private var accessory: some View {
        switch family {
        case .accessoryInline:
            Label(entry.title, systemImage: "photo.on.rectangle")
        case .accessoryCircular:
            if showsPhotos {
                photo(0).clipShape(Circle())
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "photo.on.rectangle")
                }
            }
        default:
            HStack(spacing: 8) {
                if showsPhotos {
                    photo(0)
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.title)
                        .font(.custom("Selawik-Semilight", size: 17))
                        .widgetAccentable()
                    Text("luminux")
                        .font(.caption)
                        .opacity(0.7)
                }
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static let gutter: CGFloat = 3

    private var lockedFace: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "lock")
                .font(.system(size: 22, weight: .light))
            Spacer()
            // A plain fact, no pitch or paywall link: App Review bars marketing inside widgets.
            Text("This size needs Luminux Pro.")
                .font(.custom("Selawik-Semilight", size: 15))
            Text("photos")
                .font(.custom("Selawik-Semilight", size: 15))
                .opacity(0.7)
        }
        .foregroundStyle(onAccent)
        .widgetAccentable()
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var tile: some View {
        if family == .systemSmall && !showsBackground && showsPhotos && entry.showsStandBy {
            standBy
        } else if entry.style == .peek && showsPhotos {
            peekingTile
        } else {
            homeTile
        }
    }

    /// Like a Windows Phone peek tile: now and then the photos slide up to show what the tile is, then drop back.
    private var peekingTile: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                homeTile.frame(height: geo.size.height)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.custom("Selawik-Semilight", size: family == .systemSmall ? 22 : 28))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(entry.date.formatted(.dateTime.weekday(.wide).day().month(.wide)).lowercased())
                        .font(.custom("Selawik-Semilight", size: 13))
                        .opacity(0.8)
                }
                .foregroundStyle(onAccent)
                .widgetAccentable()
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .frame(height: geo.size.height)
                .background(Color(hex: entry.accentHex))
            }
            .offset(y: entry.isPeeking ? -geo.size.height * 0.55 : 0)
            .animation(.smooth(duration: 0.7), value: entry.isPeeking)
        }
        .clipped()
    }

    /// Like a corner of the hub: three photo tiles and today's date on an accent tile.
    private var standBy: some View {
        Grid(horizontalSpacing: Self.gutter * 2, verticalSpacing: Self.gutter * 2) {
            GridRow {
                photo(0)
                // Bottom-aligned, clear of the rounded corner StandBy and the Home Screen cut into this tile.
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 0)
                    Text(entry.date.formatted(.dateTime.day()))
                        .font(.custom("Selawik-Light", size: 44))
                    Text(entry.date.formatted(.dateTime.weekday(.wide).month(.abbreviated)).lowercased())
                        .font(.custom("Selawik-Semilight", size: 13))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(onAccent)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(Color(hex: entry.accentHex))
            }
            GridRow {
                photo(1)
                photo(2)
            }
        }
    }

    private var homeTile: some View {
        ZStack(alignment: .bottomLeading) {
            if entry.needsCollection {
                Text("Touch and hold, then Edit Widget to choose a collection.")
                    .font(.custom("Selawik-Semilight", size: 15))
                    .foregroundStyle(onAccent)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if entry.imageURLs.isEmpty {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 40, weight: .ultraLight))
                    .foregroundStyle(onAccent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                collage
            }
            Text(entry.title)
                .font(.custom("Selawik-Semilight", size: 15))
                .foregroundStyle(showsPhotos ? .white : onAccent)
                .widgetAccentable()
                .padding(12)
        }
        .overlay(alignment: .topTrailing) {
            // Not on the small tile: there a tap anywhere opens the app.
            if family != .systemSmall && showsPhotos {
                Button(intent: ShuffleTileIntent()) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(.black.opacity(0.45), in: Circle())
                        .widgetAccentable()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Shuffle photos")
                .padding(8)
            }
        }
    }

    @ViewBuilder
    private var collage: some View {
        if entry.style == .mosaic {
            let mosaic = TileProvider.mosaic(for: family)
            Grid(horizontalSpacing: Self.gutter, verticalSpacing: Self.gutter) {
                ForEach(0..<mosaic.rows, id: \.self) { row in
                    GridRow {
                        ForEach(0..<mosaic.columns, id: \.self) { column in
                            photo(row * mosaic.columns + column)
                        }
                    }
                }
            }
        } else {
            switch family {
            case .systemSmall:
                // The newest photo always lands on top as it slides in.
                photo(entry.changed ?? 0, layer: entry.generations.reduce(0, +))
            case .systemMedium:
                HStack(spacing: Self.gutter) {
                    photo(0)
                    VStack(spacing: Self.gutter) {
                        photo(1)
                        photo(2)
                    }
                }
            default:
                Grid(horizontalSpacing: Self.gutter, verticalSpacing: Self.gutter) {
                    GridRow {
                        photo(0)
                        photo(1)
                    }
                    GridRow {
                        photo(2)
                        photo(3)
                    }
                }
            }
        }
    }

    /// The changed photo slides in over the old one from the entry's side; the old one sinks back and fades. The
    /// old photo's way out doesn't depend on a side, so it can't disagree with the new one's.
    private func photo(_ slot: Int, layer: Int? = nil) -> some View {
        let images = entry.imageURLs
        let url = images[safe: slot] ?? images[0]
        return Color.clear
            .overlay {
                if let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image).resizable()
                        // Without a mode, a tinted or clear Home Screen draws photos as flat white shapes; tinted
                        // like everything else there, they sit with the rest of the Home Screen.
                        .widgetAccentedRenderingMode(renderingMode == .accented ? .accentedDesaturated : .fullColor)
                        .scaledToFill()
                        .id(url)
                        .zIndex(Double(layer ?? entry.generations[safe: slot] ?? 0))
                        .transition(transition)
                }
            }
            .animation(.smooth(duration: 0.7), value: url)
            .clipped()
    }

    private var transition: AnyTransition {
        guard entry.style == .flip else {
            return .asymmetric(insertion: .move(edge: entry.side.edge), removal: .scale(scale: 0.9).combined(with: .opacity))
        }
        // The hub's flip: the old photo turns away edge-on, then the new one turns in from the other side.
        return .asymmetric(
            insertion: .modifier(active: FlipFace(angle: -90), identity: FlipFace(angle: 0)).animation(.easeOut(duration: 0.3).delay(0.25)),
            removal: .modifier(active: FlipFace(angle: 90), identity: FlipFace(angle: 0)).animation(.easeIn(duration: 0.25))
        )
    }
}

/// One face of a flipping tile, turned about its horizontal middle.
private struct FlipFace: ViewModifier {
    let angle: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .opacity(abs(angle) < 90 ? 1 : 0)
    }
}

extension TileShuffle.Side {
    var edge: Edge {
        switch self {
        case .top: .top
        case .bottom: .bottom
        case .leading: .leading
        case .trailing: .trailing
        }
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
