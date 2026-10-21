import CoreGraphics
import QuartzCore
import Testing
@testable import Luminux

struct GridZoomTests {
    @Test func levelsAddTheSameColumnsOnEitherSide() {
        #expect(GridZoom.levels == [3, 5, 7, 15])
        for (fewer, more) in zip(GridZoom.levels, GridZoom.levels.dropFirst()) {
            #expect((more - fewer) % 2 == 0)
        }
    }

    @Test func aPinchHeadsToTheNextLevelEitherWay() {
        // 5 columns drawn at 1.4× look like 3.6 columns.
        #expect(GridZoom.level(toward: 5 / 1.4, from: 5) == 3)
        #expect(GridZoom.level(toward: 5 / 0.7, from: 5) == 7)
        #expect(GridZoom.level(toward: 7 / 0.7, from: 7) == 15)
        #expect(GridZoom.level(toward: 5, from: 5) == nil)
        #expect(GridZoom.level(toward: 2, from: 3) == nil)
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
        // The levels that are gone come back as the biggest photos there are.
        #expect(GridZoom.nearestLevel(to: 2) == 3)
        #expect(GridZoom.nearestLevel(to: 1) == 3)
    }

    @Test func onePinchCanGoThroughEveryLevel() {
        // From 3, the grid follows the fingers all the way to 15 columns, and from 15 back to 3.
        let fromFewest = GridZoom.scaleLimits(for: 3)
        #expect(abs(fromFewest.lowerBound - 3.0 / 15) < 0.001 && fromFewest.upperBound == 1)
        #expect(GridZoom.rubberBand(0.3, limits: fromFewest) == 0.3)
        let fromMost = GridZoom.scaleLimits(for: 15)
        #expect(fromMost.lowerBound == 1 && fromMost.upperBound == 5)
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

    /// A month title and the gap under it.
    private let title = GridLayout.headerHeight + 4

    @Test func photosSitUnderTheirMonthTitleRowByRow() {
        #expect(layout.side == 96)
        // First month: its title, then two rows.
        #expect(layout.frame(of: 0) == CGRect(x: 0, y: title, width: 96, height: 96))
        #expect(layout.frame(of: 5) == CGRect(x: 100, y: title + 100, width: 96, height: 96))
        // Second month starts after two rows, its title, then its photo.
        #expect(layout.headerTop(ofSectionAt: 1) == title + 200)
        #expect(layout.frame(of: 6) == CGRect(x: 0, y: 2 * title + 200, width: 96, height: 96))
        #expect(layout.frame(of: 7) == nil)
        #expect(layout.height == 2 * title + 200 + 96 + GridLayout.bottomPadding)
    }

    @Test func aPointFindsItsPhotoAndTheNearestOneOffAPhoto() {
        #expect(layout.index(at: CGPoint(x: 150, y: title + 12)) == 1)
        // In a gap, over a title, past the last photo of a row.
        #expect(layout.index(at: CGPoint(x: 98, y: title + 12)) == nil)
        #expect(layout.index(at: CGPoint(x: 10, y: 20)) == nil)
        #expect(layout.index(at: CGPoint(x: 350, y: title + 112)) == nil)
        #expect(layout.index(nearest: CGPoint(x: 98, y: title + 12)) == 0)
        #expect(layout.index(nearest: CGPoint(x: 10, y: 20)) == 0)
        #expect(layout.index(nearest: CGPoint(x: 350, y: title + 112)) == 5)
    }

    @Test func onlyWhatMeetsARectIsDrawn() {
        #expect(layout.indices(in: CGRect(x: 0, y: 0, width: 396, height: title + 52)) == [0, 1, 2, 3])
        #expect(layout.indices(in: CGRect(x: 0, y: title + 150, width: 396, height: 200)) == [4, 5, 6])
        #expect(layout.headers(in: CGRect(x: 0, y: title + 150, width: 396, height: 200)).map(\.position) == [1])
    }

    @Test func staggerRowsCountMonthTitles() {
        #expect(layout.cell(of: 0)! == (1, 0))
        #expect(layout.cell(of: 5)! == (2, 1))
        // Title row 3, photos row 4.
        #expect(layout.cell(of: 6)! == (4, 0))
        #expect(layout.row(atY: title + 204) == 4)
    }

    @Test func withoutMonthsThePhotosStartAtTheTop() {
        let plain = GridLayout(columns: 3, width: 308, gutter: 4, sections: nil, count: 4)
        #expect(plain.frame(of: 3) == CGRect(x: 0, y: 104, width: 100, height: 100))
        #expect(plain.headers(in: CGRect(x: 0, y: 0, width: 308, height: 1000)).isEmpty)
    }

    @Test func middleBlockDissolvesWithoutDimming() {
        let old = PinchTile(index: 0, kind: .shown, unsorted: .zero)
        let new = PinchTile(index: 0, kind: .sortedMiddle, unsorted: .zero)
        for step in 0...20 {
            let sortedness = CGFloat(step) / 20
            let top = old.opacity(at: .unsorted, progress: 1, sortedness: sortedness)
            let under = new.opacity(at: .unsorted, progress: 1, sortedness: sortedness)
            // How much of the cell is covered, the old photo drawn over the new one.
            #expect(top + under * (1 - top) >= 0.93)
        }
    }

    @Test func sortFollowsThePinch() {
        let range: ClosedRange<CGFloat> = 0.3...0.85
        #expect(GridPinch.sortedness(at: 0.2, over: range) == 0)
        #expect(GridPinch.sortedness(at: 0.9, over: range) == 1)
        #expect(abs(GridPinch.sortedness(at: 0.575, over: range) - 0.5) < 0.001)
        var last: CGFloat = 0
        for step in 0...20 {
            let value = GridPinch.sortedness(at: CGFloat(step) / 20, over: range)
            #expect(value >= last)
            last = value
        }
    }

    @Test func releaseFinishesAtTheFingersSpeed() {
        // A flick finishes fast, a slow release eases in, still fingers take the default, and it's never instant.
        #expect(AssetGrid.settleDuration(distance: 0.5, speed: 20) == 0.15)
        #expect(AssetGrid.settleDuration(distance: 0.5, speed: 1) == 0.45)
        #expect(AssetGrid.settleDuration(distance: 0.5, speed: 0) == 0.4)
        #expect(AssetGrid.settleDuration(distance: 0.5, speed: 4) == 0.25)
    }

    @Test func releaseCurveStartsAtTheFingersSpeed() {
        func firstControlPoint(_ slope: CGFloat) -> (Float, Float) {
            var point = [Float](repeating: 0, count: 2)
            AssetGrid.settleCurve(initialSlope: slope).getControlPoint(at: 1, values: &point)
            return (point[0], point[1])
        }
        // The curve leaves at y/x of its first control point.
        let (x, y) = firstControlPoint(2)
        #expect(abs(y / x - 2) < 0.001)
        // Still fingers start from rest; a flick can't leave faster than the curve allows.
        #expect(firstControlPoint(0).1 == 0)
        #expect(firstControlPoint(50).1 == 1)
    }

    @Test func pinchTilesMoveCentreToCentre() {
        let tile = PinchTile(index: 0, kind: .shown, unsorted: CGRect(x: 0, y: 200, width: 100, height: 150),
                             start: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(tile.center(at: 0) == CGPoint(x: 50, y: 50))
        #expect(tile.center(at: 1) == CGPoint(x: 50, y: 275))
    }
}
