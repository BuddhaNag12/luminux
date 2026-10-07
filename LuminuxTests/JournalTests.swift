import Foundation
import Testing
@testable import Luminux

struct JournalTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private static let locale = Locale(identifier: "en_US")

    private let home = Coordinate(latitude: 22.57, longitude: 88.36)
    private let away = Coordinate(latitude: 15.49, longitude: 73.83)

    /// Saturday 4 October 2026, at the given hour and minute, plus whole days.
    private func date(day: Int = 0, hour: Int, minute: Int = 0) -> Date {
        Self.calendar.date(from: DateComponents(year: 2026, month: 10, day: 3 + day, hour: hour, minute: minute))!
    }

    private func photos(_ count: Int, day: Int = 0, hour: Int, at place: Coordinate?, prefix: String) -> [PhotoPoint] {
        (0..<count).map { PhotoPoint(id: "\(prefix)\($0)", date: date(day: day, hour: hour, minute: $0 * 5), coordinate: place, isFavorite: false) }
    }

    /// Everyday photos at home over a few weeks, so the builder knows where home is.
    private var homeBase: [PhotoPoint] {
        (1...6).flatMap { photos(1, day: -7 * $0, hour: 10, at: home, prefix: "base\($0)-") }
    }

    private func entries(_ points: [PhotoPoint]) -> [JournalEntry] {
        JournalBuilder.entries(from: points, calendar: Self.calendar)
    }

    @Test func photosCloseTogetherMakeOneMoment() {
        let result = entries(homeBase + photos(4, hour: 14, at: home, prefix: "a"))
        let moment = result.first { $0.photoIDs.contains("a0") }

        #expect(moment?.kind == .moment)
        #expect(moment?.photoIDs == ["a0", "a1", "a2", "a3"])
        #expect(moment?.isAway == false)
    }

    @Test func aLongGapStartsANewMoment() {
        let result = entries(homeBase + photos(3, hour: 9, at: home, prefix: "a") + photos(3, hour: 18, at: home, prefix: "b"))

        #expect(result.contains { $0.photoIDs == ["a0", "a1", "a2"] })
        #expect(result.contains { $0.photoIDs == ["b0", "b1", "b2"] })
    }

    @Test func movingFarStartsANewMoment() {
        let nearby = Coordinate(latitude: 22.9, longitude: 88.36)
        let result = entries(homeBase + photos(3, hour: 9, at: home, prefix: "a") + photos(3, hour: 10, at: nearby, prefix: "b"))

        #expect(result.contains { $0.photoIDs == ["a0", "a1", "a2"] })
        #expect(result.contains { $0.photoIDs == ["b0", "b1", "b2"] })
    }

    @Test func strayPhotosMakeADayOnlyWhenNothingElseHappened() {
        let stray = [9, 13, 19].enumerated().map { index, hour in
            PhotoPoint(id: "s\(index)", date: date(hour: hour), coordinate: home, isFavorite: false)
        }
        let quietDay = entries(homeBase + stray)
        #expect(quietDay.contains { $0.kind == .day && $0.photoIDs == ["s0", "s1", "s2"] })

        let busyDay = entries(homeBase + stray + photos(4, hour: 15, at: home, prefix: "m"))
        #expect(!busyDay.contains { $0.kind == .day })
    }

    @Test func daysAwayBecomeOneTrip() {
        let trip = photos(4, day: 0, hour: 10, at: away, prefix: "t0-")
            + photos(4, day: 1, hour: 11, at: away, prefix: "t1-")
            + photos(4, day: 2, hour: 12, at: away, prefix: "t2-")
        let result = entries(homeBase + trip)
        let entry = result.first { $0.kind == .trip }

        #expect(entry?.photoIDs.count == 12)
        #expect(entry?.isAway == true)
        #expect(!result.contains { $0.kind == .moment && $0.isAway })
    }

    @Test func oneDayAwayIsAnAwayMomentNotATrip() {
        let result = entries(homeBase + photos(4, hour: 15, at: away, prefix: "x"))

        #expect(!result.contains { $0.kind == .trip })
        #expect(result.contains { $0.kind == .moment && $0.isAway })
    }

    @Test func entriesComeNewestFirst() {
        let result = entries(homeBase + photos(3, day: 0, hour: 9, at: home, prefix: "old") + photos(3, day: 5, hour: 9, at: home, prefix: "new"))

        #expect(result.first?.photoIDs.first == "new0")
    }

    @Test func titlesReadLikeTheOriginal() {
        func title(_ kind: JournalEntry.Kind, isAway: Bool, place: String?, days: Int = 0, hour: Int = 15) -> String {
            let entry = JournalEntry(
                id: "e", kind: kind, start: date(hour: hour), end: date(day: days, hour: hour + 1),
                photoIDs: ["e"], favoriteIDs: [], center: away, isAway: isAway
            )
            return JournalTitles.title(for: entry, place: place, calendar: Self.calendar, locale: Self.locale)
        }

        #expect(title(.moment, isAway: false, place: "Kolkata") == "saturday afternoon")
        #expect(title(.moment, isAway: true, place: "Goa") == "afternoon in goa")
        #expect(title(.moment, isAway: true, place: nil, hour: 8) == "saturday morning")
        #expect(title(.trip, isAway: true, place: "Jaipur", days: 3) == "trip to jaipur")
        #expect(title(.trip, isAway: true, place: nil, days: 3) == "4 days away")
        #expect(title(.day, isAway: false, place: nil) == "saturday")
    }

    @Test func spreadPicksEvenlyFromStartToEnd() {
        let ids = (0..<10).map(String.init)

        #expect(Journal.spread(ids, count: 3) == ["0", "5", "9"])
        #expect(Journal.spread(["a", "b"], count: 3) == ["a", "b"])
    }

    @Test func homeIsWherePhotosAreTakenOnTheMostDays() {
        // More photos on a two-day trip than at home, but home has more days.
        let points = homeBase + photos(10, day: 0, hour: 10, at: away, prefix: "t0-") + photos(10, day: 1, hour: 10, at: away, prefix: "t1-")

        let found = JournalBuilder.homePlace(of: points, calendar: Self.calendar)
        #expect(found.map { $0.distance(to: home) < 1000 } == true)
    }
}
