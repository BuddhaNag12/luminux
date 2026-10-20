import CoreGraphics
import Testing
@testable import Luminux

struct GridZoomTests {
    @Test func levelsAddTheSameColumnsOnEitherSide() {
        #expect(GridZoom.levels == [2, 3, 5, 7, 15])
        for (fewer, more) in zip(GridZoom.levels.dropFirst(), GridZoom.levels.dropFirst(2)) {
            #expect((more - fewer) % 2 == 0)
        }
    }

    @Test func aPinchHeadsToTheNextLevelEitherWay() {
        // 5 columns drawn at 1.4× look like 3.6 columns.
        #expect(GridZoom.level(toward: 5 / 1.4, from: 5) == 3)
        #expect(GridZoom.level(toward: 5 / 0.7, from: 5) == 7)
        #expect(GridZoom.level(toward: 7 / 0.7, from: 7) == 15)
        #expect(GridZoom.level(toward: 5, from: 5) == nil)
        #expect(GridZoom.level(toward: 2, from: 3) == 2)
        #expect(GridZoom.level(toward: 1, from: 2) == nil)
        #expect(GridZoom.level(toward: 20, from: 15) == nil)
    }

    @Test func progressIsHalfwayAtTheLogMidpoint() {
        #expect(GridZoom.progress(3, from: 3, to: 5) == 0)
        #expect(GridZoom.progress(5, from: 3, to: 5) == 1)
        #expect(abs(GridZoom.progress(sqrt(15), from: 3, to: 5) - 0.5) < 0.001)
        #expect(GridZoom.progress(9, from: 3, to: 5) == 1)
        // Pinching the other way counts from the same start.
        #expect(abs(GridZoom.progress(sqrt(75), from: 15, to: 5) - 0.5) < 0.001)
    }

    @Test func savedColumnCountsSnapToALevel() {
        #expect(GridZoom.nearestLevel(to: 4) == 3)
        #expect(GridZoom.nearestLevel(to: 8) == 7)
        #expect(GridZoom.nearestLevel(to: 20) == 15)
    }

    @Test func onePinchCanGoThroughEveryLevel() {
        // From 2, the grid follows the fingers all the way to 15 columns, and from 15 back to 2.
        let fromFewest = GridZoom.scaleLimits(for: 2)
        #expect(abs(fromFewest.lowerBound - 2.0 / 15) < 0.001 && fromFewest.upperBound == 1)
        #expect(GridZoom.rubberBand(0.3, limits: fromFewest) == 0.3)
        let fromMost = GridZoom.scaleLimits(for: 15)
        #expect(fromMost.lowerBound == 1 && fromMost.upperBound == 7.5)
    }

    @Test func pastTheEndLevelsTheGridResists() {
        let stretched = GridZoom.rubberBand(2, limits: GridZoom.scaleLimits(for: 2))
        #expect(stretched > 1 && stretched < 1.5)
        let squeezed = GridZoom.rubberBand(0.5, limits: GridZoom.scaleLimits(for: 15))
        #expect(squeezed < 1 && squeezed > 0.8)
    }

    @Test func theSmallestPhotosCantBeSelected() {
        #expect(GridZoom.allowsSelection(columns: 7))
        #expect(!GridZoom.allowsSelection(columns: 15))
        let selection = SelectionModel()
        selection.isAllowed = false
        selection.begin(with: "a")
        #expect(!selection.isActive && selection.selectedIDs.isEmpty)
    }

    // 4 columns of 96 with a 4 gap make a 396 wide grid: pitch 100.
    private let layout = GridLayout(columns: 4, width: 396, gutter: 4, sections: [0..<6, 6..<7], count: 7)

    @Test func photosSitUnderTheirMonthTitleRowByRow() {
        #expect(layout.side == 96)
        // First month: title 44 + gap 4, then two rows.
        #expect(layout.frame(of: 0) == CGRect(x: 0, y: 48, width: 96, height: 96))
        #expect(layout.frame(of: 5) == CGRect(x: 100, y: 148, width: 96, height: 96))
        // Second month starts after two rows: 48 + 200, its title, then its photo.
        #expect(layout.headerTop(ofSectionAt: 1) == 248)
        #expect(layout.frame(of: 6) == CGRect(x: 0, y: 296, width: 96, height: 96))
        #expect(layout.frame(of: 7) == nil)
        #expect(layout.height == 296 + 96 + GridLayout.bottomPadding)
    }

    @Test func aPointFindsItsPhotoAndTheNearestOneOffAPhoto() {
        #expect(layout.index(at: CGPoint(x: 150, y: 60)) == 1)
        // In a gap, over a title, past the last photo of a row.
        #expect(layout.index(at: CGPoint(x: 98, y: 60)) == nil)
        #expect(layout.index(at: CGPoint(x: 10, y: 20)) == nil)
        #expect(layout.index(at: CGPoint(x: 350, y: 160)) == nil)
        #expect(layout.index(nearest: CGPoint(x: 98, y: 60)) == 0)
        #expect(layout.index(nearest: CGPoint(x: 10, y: 20)) == 0)
        #expect(layout.index(nearest: CGPoint(x: 350, y: 160)) == 5)
    }

    @Test func onlyWhatMeetsARectIsDrawn() {
        #expect(layout.indices(in: CGRect(x: 0, y: 0, width: 396, height: 100)) == [0, 1, 2, 3])
        #expect(layout.indices(in: CGRect(x: 0, y: 150, width: 396, height: 200)) == [4, 5, 6])
        #expect(layout.headers(in: CGRect(x: 0, y: 150, width: 396, height: 200)).map(\.position) == [1])
    }

    @Test func staggerRowsCountMonthTitles() {
        #expect(layout.cell(of: 0)! == (1, 0))
        #expect(layout.cell(of: 5)! == (2, 1))
        // Title row 3, photos row 4.
        #expect(layout.cell(of: 6)! == (4, 0))
        #expect(layout.row(atY: 300) == 4)
    }

    @Test func withoutMonthsThePhotosStartAtTheTop() {
        let plain = GridLayout(columns: 3, width: 308, gutter: 4, sections: nil, count: 4)
        #expect(plain.frame(of: 3) == CGRect(x: 0, y: 104, width: 100, height: 100))
        #expect(plain.headers(in: CGRect(x: 0, y: 0, width: 308, height: 1000)).isEmpty)
    }
}
