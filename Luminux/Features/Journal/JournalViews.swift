import Photos
import SwiftUI

/// An entry's best photos: one large, two stacked beside it when there are enough.
struct JournalMosaic: View {
    let entry: JournalEntry

    @Environment(Journal.self) private var journal
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let assets = Self.assets(for: journal.keyPhotos(for: entry, count: 3))
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

    /// In the order asked for; a fetch by identifier comes back in library order.
    private static func assets(for ids: [String]) -> [PHAsset] {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var byID: [String: PHAsset] = [:]
        result.enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }
        return ids.compactMap { byID[$0] }
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
    @Environment(\.metro) private var metro
    @State private var selection = SelectionModel()
    @State private var isAppBarExpanded = false
    @State private var isRenaming = false
    @State private var newTitle = ""
    @State private var isEditingNote = false
    @State private var bottomInset: CGFloat = 0

    var body: some View {
        let entry = journal.entry(id: entryID)
        VStack(alignment: .leading, spacing: 0) {
            Text("LUMINUX · JOURNAL")
                .font(.metroOverline)
                .tracking(1.5)
                .padding(.leading, MetroMetrics.margin + 4)
                .metroFeather(row: 0)

            if let entry {
                VStack(alignment: .leading, spacing: 4) {
                    Text(journal.title(for: entry))
                        .font(.metro(40, .light))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .accessibilityAddTraits(.isHeader)
                    Text(journal.subtitle(for: entry))
                        .font(.metroCaption)
                        .foregroundStyle(metro.secondary)
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
                .padding(.bottom, 12)
                .metroFeather(row: 0)

                AssetGrid(
                    source: .identifiers(entry.photoIDs),
                    selection: selection,
                    emptyMessage: "These photos are no longer in your library.",
                    jumpTarget: .constant(nil)
                )
                .contentMargins(.bottom, bottomInset, for: .scrollContent)
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
        .metroAppBar(entry == nil ? [] : buttons, isExpanded: $isAppBarExpanded)
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

    private var buttons: [AppBarButton] {
        [
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
            TextEditor(text: $text)
                .font(.metroBody)
                .scrollContentBackground(.hidden)
                .padding(8)
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
        }
        .padding(.horizontal, MetroMetrics.margin + 12)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .foregroundStyle(metro.foreground)
        .background(metro.background)
        .presentationDetents([.medium, .large])
        .onAppear {
            text = journal.note(for: entry) ?? ""
            isFocused = true
        }
    }
}
