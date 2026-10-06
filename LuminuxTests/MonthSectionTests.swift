import Foundation
import Testing
@testable import Luminux

struct MonthSectionTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func emptyInputHasNoSections() {
        #expect(MonthSection.group([], calendar: calendar).isEmpty)
    }

    @Test func groupsContiguousMonthsNewestFirst() {
        let dates = [date(2026, 10, 6), date(2026, 10, 1), date(2026, 9, 30), date(2025, 9, 12)]
        let sections = MonthSection.group(dates, calendar: calendar)

        #expect(sections.map(\.year) == [2026, 2026, 2025])
        #expect(sections.map(\.month) == [10, 9, 9])
        #expect(sections.map(\.range) == [0..<2, 2..<3, 3..<4])
    }

    @Test func undatedAssetsGetTheirOwnSection() {
        let sections = MonthSection.group([date(2026, 1, 5), nil, nil], calendar: calendar)

        #expect(sections.count == 2)
        #expect(sections[1].isUndated)
        #expect(sections[1].range == 1..<3)
        #expect(sections[1].title(calendar: calendar) == "undated")
    }

    @Test func titleIsLowercaseMonthAndYear() {
        let section = MonthSection(year: 2026, month: 10, range: 0..<1)
        #expect(section.title(calendar: calendar, locale: Locale(identifier: "en_US")) == "october 2026")
    }

    @Test func idsStayUniqueWhenAMonthRepeats() {
        let sections = MonthSection.group([date(2026, 3, 1), date(2026, 2, 1), date(2026, 3, 1)], calendar: calendar)
        #expect(Set(sections.map(\.id)).count == 3)
    }
}
