import CoreGraphics
import Testing
@testable import Luminux

struct TiltTests {
    private let size = CGSize(width: 100, height: 100)

    @Test func pressingTheCentrePushesInWithoutTipping() {
        let tilt = Tilt.pressed(at: CGPoint(x: 50, y: 50), in: size)
        #expect(tilt.angle == 0)
        #expect(tilt.scale < 1)
    }

    @Test func pressingAnEdgeTipsAroundTheOtherAxis() {
        let right = Tilt.pressed(at: CGPoint(x: 100, y: 50), in: size)
        #expect(right.angle > 0)
        #expect(right.axisX == 0)
        #expect(right.axisY > 0)

        let top = Tilt.pressed(at: CGPoint(x: 50, y: 0), in: size)
        #expect(top.axisY == 0)
        #expect(top.axisX > 0)
    }

    @Test func touchesOutsideTheTileAreClamped() {
        let inside = Tilt.pressed(at: CGPoint(x: 100, y: 50), in: size)
        let outside = Tilt.pressed(at: CGPoint(x: 400, y: 50), in: size)
        #expect(inside == outside)
    }

    @Test func largeTilesTipLess() {
        let small = Tilt.pressed(at: CGPoint(x: 100, y: 50), in: size)
        let large = Tilt.pressed(at: CGPoint(x: 360, y: 180), in: CGSize(width: 360, height: 360))
        #expect(large.angle < small.angle)
    }

    @Test func unknownTouchStillPressesIn() {
        let tilt = Tilt.pressed(at: nil, in: size)
        #expect(tilt.angle == 0)
        #expect(tilt.scale < 1)
    }
}

struct JumpListTests {
    @Test func groupsMonthsByYearNewestFirst() {
        let sections = [
            MonthSection(year: 2026, month: 10, range: 0..<3),
            MonthSection(year: 2026, month: 9, range: 3..<4),
            MonthSection(year: 2025, month: 12, range: 4..<6),
        ]
        let years = JumpListYear.years(from: sections)

        #expect(years.map(\.year) == [2026, 2025])
        #expect(years[0].sectionIDs.keys.sorted() == [9, 10])
        #expect(years[1].sectionIDs[12] == sections[2].id)
    }

    @Test func repeatedMonthJumpsToItsFirstSection() {
        let first = MonthSection(year: 2026, month: 3, range: 0..<1)
        let sections = [first, MonthSection(year: 2026, month: 2, range: 1..<2), MonthSection(year: 2026, month: 3, range: 2..<3)]

        #expect(JumpListYear.years(from: sections)[0].sectionIDs[3] == first.id)
    }

    @Test func undatedSectionsAreLeftOut() {
        let sections = [MonthSection(year: 0, month: 0, range: 0..<2)]
        #expect(JumpListYear.years(from: sections).isEmpty)
    }
}
