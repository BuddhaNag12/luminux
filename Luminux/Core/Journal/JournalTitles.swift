import Foundation

/// Generated entry titles in the Metro voice: "saturday afternoon", "evening in goa", "trip to jaipur".
nonisolated enum JournalTitles {
    static func title(for entry: JournalEntry, place: String?, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let place = entry.isAway ? place?.lowercased(with: locale) : nil
        let weekday = entry.start.formatted(Date.FormatStyle(locale: locale, calendar: calendar).weekday(.wide)).lowercased(with: locale)
        switch entry.kind {
        case .trip:
            return place.map { "trip to \($0)" } ?? "\(dayCount(entry, calendar: calendar)) days away"
        case .day:
            return place.map { "a day in \($0)" } ?? weekday
        case .moment:
            let time = timeOfDay(entry.start, calendar: calendar)
            return place.map { "\(time) in \($0)" } ?? "\(weekday) \(time)"
        }
    }

    /// "saturday, 4 october 2026 · 12 photos", or a date range for entries that span days.
    static func subtitle(for entry: JournalEntry, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: calendar)
        let dates = calendar.isDate(entry.start, inSameDayAs: entry.end)
            ? entry.start.formatted(style.weekday(.wide).day().month(.wide).year())
            : (entry.start..<entry.end).formatted(Date.IntervalFormatStyle(locale: locale, calendar: calendar).day().month(.wide).year())
        let count = entry.photoIDs.count
        return "\(dates.lowercased(with: locale)) · \(count) \(count == 1 ? "photo" : "photos")"
    }

    static func timeOfDay(_ date: Date, calendar: Calendar) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: "morning"
        case 12..<17: "afternoon"
        case 17..<21: "evening"
        default: "night"
        }
    }

    static func dayCount(_ entry: JournalEntry, calendar: Calendar) -> Int {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: entry.start), to: calendar.startOfDay(for: entry.end)).day ?? 0
        return days + 1
    }
}
