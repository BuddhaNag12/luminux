import Photos
import SwiftUI

/// An entry's best photos: one large, two stacked beside it when there are enough.
struct JournalMosaic: View {
    let entry: JournalEntry

    @Environment(Journal.self) private var journal
    @Environment(PhotoLibrary.self) private var library
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let assets = journal.keyPhotos(for: entry, count: 3).compactMap(library.asset(id:))
        GeometryReader { geo in
            let gutter = MetroMetrics.gutter
            let showsSide = assets.count >= 3
            let sideWidth = showsSide ? (geo.size.width - gutter) / 3 : 0
            let coverWidth = showsSide ? geo.size.width - gutter - sideWidth : geo.size.width
            HStack(spacing: gutter) {
                if let cover = assets.first {
                    AssetThumbnail(asset: cover, pixelSide: max(coverWidth, geo.size.height) * displayScale)
                        .frame(width: coverWidth, height: geo.size.height)
                }
                if showsSide {
                    let side = (geo.size.height - gutter) / 2
                    VStack(spacing: gutter) {
                        ForEach(assets[1...2], id: \.localIdentifier) { asset in
                            AssetThumbnail(asset: asset, pixelSide: max(sideWidth, side) * displayScale)
                                .frame(width: sideWidth, height: side)
                        }
                    }
                }
            }
        }
        .task(id: entry.id) { await journal.scoreKeyPhotos(for: entry) }
        .accessibilityHidden(true)
    }
}

struct JournalEntryTile: View {
    let entry: JournalEntry

    @Environment(Journal.self) private var journal
    @Environment(Navigator.self) private var navigator
    @Environment(\.metro) private var metro

    var body: some View {
        Button {
            navigator.push(.journalEntry(entry.id))
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                JournalMosaic(entry: entry)
                    .aspectRatio(16.0 / 10, contentMode: .fit)
                    .padding(.bottom, 6)
                Text(journal.title(for: entry))
                    .font(.metro(22, .semilight))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(journal.subtitle(for: entry))
                    .font(.metroCaption)
                    .foregroundStyle(metro.foreground.opacity(0.7))
                if let note = journal.note(for: entry) {
                    Text(note)
                        .font(.metroBody)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(TiltButtonStyle(touch: nil, size: .zero))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this journal entry")
    }
}

/// Shown while the journal is built, and when there's nothing to put in it.
struct JournalPlaceholder: View {
    @Environment(Journal.self) private var journal
    @Environment(\.metro) private var metro

    var body: some View {
        Text(journal.isBuilt
             ? "Outings, days and trips show up here on their own as you take photos."
             : "Putting your journal together…")
            .font(.metroBody)
            .foregroundStyle(metro.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Every entry, newest first, under year headers.
struct JournalView: View {
    @Environment(Journal.self) private var journal
    @Environment(\.metro) private var metro

    var body: some View {
        let years = Dictionary(grouping: journal.entries) { Calendar.current.component(.year, from: $0.start) }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("LUMINUX").font(.metroOverline).tracking(1.5)
                    Text("journal")
                        .font(.metroTitle)
                        .padding(.leading, -3)
                }
                .metroFeather(row: 0)

                if journal.entries.isEmpty {
                    JournalPlaceholder().metroFeather(row: 1)
                }

                ForEach(Array(years.keys.sorted(by: >).enumerated()), id: \.element) { yearIndex, year in
                    Text(String(year))
                        .font(.metro(20, .semilight))
                        .foregroundStyle(metro.accentColor)
                        .accessibilityAddTraits(.isHeader)
                        .metroFeather(row: 1 + yearIndex * 3)
                    ForEach(Array((years[year] ?? []).enumerated()), id: \.element.id) { index, entry in
                        JournalEntryTile(entry: entry)
                            .metroFeather(row: 2 + yearIndex * 3 + index)
                    }
                }
            }
            .padding(.horizontal, MetroMetrics.margin + 12)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(metro.foreground)
        .background(metro.background)
    }
}

/// One entry: its title, dates and note over all of its photos.
struct JournalEntryView: View {
    let entryID: String

    @Environment(Journal.self) private var journal
    @Environment(PhotoLibrary.self) private var library
    @Environment(Navigator.self) private var navigator
    @Environment(\.metro) private var metro
    @State private var selection = SelectionModel()
    @State private var isAppBarExpanded = false
    @State private var share: ShareItems?
    @State private var addToAlbum: AddToAlbumRequest?
    @State private var isRenaming = false
    @State private var newTitle = ""
    @State private var isEditingNote = false
    @State private var bottomInset: CGFloat = 0
    @State private var headerHeight: CGFloat = 0
    /// How far the grid has scrolled from its top; the header above the photos moves with it.
    @State private var scrolled: CGFloat = 0

    var body: some View {
        let entry = journal.entry(id: entryID)
        VStack(alignment: .leading, spacing: 0) {
            Text(selection.isActive ? "LUMINUX · \(selection.selectedIDs.count) SELECTED" : "LUMINUX · JOURNAL")
                .font(.metroOverline)
                .tracking(1.5)
                .padding(.leading, MetroMetrics.margin + 4)
                .metroFeather(row: 0)

            if let entry {
                // The grid places its photos from the top of its scroll view, so the header sits over a top margin
                // and moves with the scroll instead of going inside it.
                AssetGrid(
                    source: .identifiers(entry.photoIDs),
                    selection: selection,
                    emptyMessage: "These photos are no longer in your library.",
                    jumpTarget: .constant(nil)
                )
                .contentMargins(.top, headerHeight, for: .scrollContent)
                .contentMargins(.bottom, bottomInset, for: .scrollContent)
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in scrolled = y }
                .overlay(alignment: .top) {
                    header(entry)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                        .offset(y: -scrolled)
                }
                .clipped()
                .padding(.top, 8)
                .ignoresSafeArea(.container, edges: .bottom)
            } else {
                Text("This entry isn't in your journal any more.")
                    .font(.metroBody)
                    .foregroundStyle(metro.secondary)
                    .padding(.horizontal, MetroMetrics.margin + 4)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(metro.foreground)
        .background(metro.background)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
        .onChange(of: entry == nil) { _, isGone in
            // Deleting photos can take an entry under the minimum; leave instead of showing an empty page.
            if isGone, navigator.path.last == .journalEntry(entryID), navigator.viewer == nil { navigator.pop() }
        }
        .metroAppBar(entry == nil ? [] : buttons, menu: selection.isActive ? [AppBarMenuItem(title: "cancel selection") { selection.end() }] : [], isExpanded: $isAppBarExpanded)
        .assetActionSheets(share: $share, addToAlbum: $addToAlbum)
        .alert("Rename entry", isPresented: $isRenaming) {
            TextField("Title", text: $newTitle)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let entry { journal.rename(entry, to: newTitle) }
            }
        } message: {
            Text("Leave it empty to go back to the automatic title.")
        }
        .sheet(isPresented: $isEditingNote) {
            if let entry {
                JournalNoteEditor(entry: entry)
            }
        }
    }

    /// The entry's best photos, then its title, dates and note. Drags pass through to the grid underneath, so the
    /// header scrolls like the photos; only the note takes a tap.
    private func header(_ entry: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            JournalMosaic(entry: entry)
                .aspectRatio(16.0 / 10, contentMode: .fit)
                .allowsHitTesting(false)
                .metroFeather(row: 0)
            VStack(alignment: .leading, spacing: 4) {
                Text(journal.title(for: entry))
                    .font(.metro(40, .light))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                    .allowsHitTesting(false)
                Text(journal.subtitle(for: entry))
                    .font(.metroCaption)
                    .foregroundStyle(metro.secondary)
                    .allowsHitTesting(false)
                if let note = journal.note(for: entry) {
                    Button {
                        isEditingNote = true
                    } label: {
                        Text(note)
                            .font(.metroBody)
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                    .accessibilityHint("Edits the note")
                }
            }
            .padding(.horizontal, MetroMetrics.margin + 4)
            .padding(.top, 14)
            .padding(.bottom, 16)
            .metroFeather(row: 1)
        }
    }

    private var buttons: [AppBarButton] {
        if selection.isActive {
            return SelectionActions.buttons(
                selection: selection,
                library: library,
                share: { assets in
                    Task {
                        let urls = await ImageLoader.shared.exportOriginals(assets)
                        if !urls.isEmpty { share = ShareItems(urls: urls) }
                    }
                },
                addToAlbum: { assets in addToAlbum = AddToAlbumRequest(assets: assets) }
            )
        }
        let select = selection.isAllowed ? [AppBarButton(title: "select", systemImage: "checklist") { selection.begin() }] : []
        return select + [
            AppBarButton(title: "rename", systemImage: "pencil") {
                if let entry = journal.entry(id: entryID) { newTitle = journal.title(for: entry) }
                isRenaming = true
            },
            AppBarButton(title: "note", systemImage: "square.and.pencil") { isEditingNote = true },
        ]
    }
}

struct JournalNoteEditor: View {
    let entry: JournalEntry

    @Environment(Journal.self) private var journal
    @Environment(\.metro) private var metro
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("note")
                .font(.metroPivot)
                .accessibilityAddTraits(.isHeader)
            Text(journal.title(for: entry))
                .font(.metroCaption)
                .foregroundStyle(metro.secondary)
            // Short enough that the box and its buttons stay above the keyboard; longer notes scroll inside it.
            TextEditor(text: $text)
                .font(.metroBody)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .padding(8)
                .frame(height: 150)
                .background(metro.chrome)
                .focused($isFocused)
                .accessibilityLabel("Note")
            HStack(spacing: 12) {
                Button("save") {
                    journal.setNote(text, for: entry)
                    dismiss()
                }
                .buttonStyle(.metro)
                Button("cancel") { dismiss() }
                    .buttonStyle(.metro)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, MetroMetrics.margin + 12)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // A tap anywhere outside the text box puts the keyboard away.
        .contentShape(Rectangle())
        .onTapGesture { isFocused = false }
        .foregroundStyle(metro.foreground)
        .background(metro.background)
        .presentationDetents([.large])
        .onAppear { text = journal.note(for: entry) ?? "" }
        .task {
            // Focus once the sheet has settled, so the keyboard doesn't come up mid-presentation.
            try? await Task.sleep(for: .milliseconds(450))
            isFocused = true
        }
    }
}
