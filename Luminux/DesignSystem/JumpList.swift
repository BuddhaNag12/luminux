import SwiftUI

/// The months of one year that have photos, mapped to the first section for each month.
struct JumpListYear: Identifiable, Equatable {
    let year: Int
    let sectionIDs: [Int: String]

    var id: Int { year }

    /// Builds years newest first from sections that are already newest first. Undated sections are skipped.
    static func years(from sections: [MonthSection]) -> [JumpListYear] {
        var order: [Int] = []
        var months: [Int: [Int: String]] = [:]
        for section in sections where !section.isUndated {
            if months[section.year] == nil {
                order.append(section.year)
                months[section.year] = [:]
            }
            if months[section.year]?[section.month] == nil {
                months[section.year]?[section.month] = section.id
            }
        }
        return order.map { JumpListYear(year: $0, sectionIDs: months[$0] ?? [:]) }
    }
}

/// Month grid for jumping through a long timeline; months with photos use the accent color.
struct JumpListView: View {
    let sections: [MonthSection]
    var currentSectionID: String?
    let onSelect: (String) -> Void

    @Environment(\.metro) private var metro

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
    private let monthNames = Calendar.current.shortMonthSymbols.map { $0.lowercased() }

    var body: some View {
        let years = JumpListYear.years(from: sections)
        let current = sections.first { $0.id == currentSectionID }
        let undated = sections.first(where: \.isUndated)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                // Each year is a header row and three rows of months.
                ForEach(Array(years.enumerated()), id: \.element.id) { position, year in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(year.year))
                            .font(.metroSection)
                            .metroFeather(row: position * 4)
                            .accessibilityAddTraits(.isHeader)
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(1...12, id: \.self) { month in
                                monthTile(
                                    name: monthNames[month - 1],
                                    sectionID: year.sectionIDs[month],
                                    isCurrent: current?.year == year.year && current?.month == month
                                )
                                .metroFeather(row: position * 4 + 1 + (month - 1) / 4, column: (month - 1) % 4, spacing: 6)
                            }
                        }
                    }
                }

                if let undated {
                    LazyVGrid(columns: columns, spacing: 6) {
                        monthTile(name: "undated", sectionID: undated.id, isCurrent: current?.isUndated == true)
                            .metroFeather(row: years.count * 4)
                    }
                }
            }
            .padding(.horizontal, MetroMetrics.margin)
            .padding(.vertical, 24)
        }
        .foregroundStyle(metro.foreground)
        .background(metro.background.opacity(0.94).ignoresSafeArea())
        .featherScope()
    }

    private func monthTile(name: String, sectionID: String?, isCurrent: Bool) -> some View {
        Button {
            if let sectionID { onSelect(sectionID) }
        } label: {
            (sectionID == nil ? metro.chrome : metro.accentColor)
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .bottomLeading) {
                    Text(name)
                        .font(.metro(22, .semilight))
                        .foregroundStyle(sectionID == nil ? metro.secondary.opacity(0.5) : .white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(8)
                }
                .overlay {
                    if isCurrent { Rectangle().strokeBorder(metro.foreground, lineWidth: 2) }
                }
        }
        .buttonStyle(TiltButtonStyle(touch: nil, size: .zero))
        .disabled(sectionID == nil)
    }
}
