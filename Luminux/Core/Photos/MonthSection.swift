import Foundation

/// A contiguous run of assets taken in the same calendar month, as indexes into the fetch result.
nonisolated struct MonthSection: Identifiable, Hashable, Sendable {
    /// 0 for undated assets.
    let year: Int
    let month: Int
    let range: Range<Int>

    var id: String { "\(year)-\(month)-\(range.lowerBound)" }
    var count: Int { range.count }
    var isUndated: Bool { year == 0 }

    func title(calendar: Calendar = .current, locale: Locale = .current) -> String {
        guard !isUndated,
              let date = calendar.date(from: DateComponents(year: year, month: month, day: 1))
        else { return "undated" }
        return date.formatted(.dateTime.month(.wide).year().locale(locale)).lowercased()
    }

    /// Groups dates (already sorted newest first) into month sections.
    static func group(_ dates: [Date?], calendar: Calendar = .current) -> [MonthSection] {
        var sections: [MonthSection] = []
        var start = 0
        var current: (year: Int, month: Int)?

        for (index, date) in dates.enumerated() {
            let key = date.map { (calendar.component(.year, from: $0), calendar.component(.month, from: $0)) } ?? (0, 0)
            if let current, current != key {
                sections.append(MonthSection(year: current.year, month: current.month, range: start..<index))
                start = index
            }
            current = key
        }
        if let current {
            sections.append(MonthSection(year: current.year, month: current.month, range: start..<dates.count))
        }
        return sections
    }
}
