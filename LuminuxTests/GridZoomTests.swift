import CoreGraphics
import Testing
@testable import Luminux

struct GridZoomTests {
    @Test func levelsAddTheSameColumnsOnEitherSide() {
        #expect(GridZoom.levels == [3, 5, 15])
        for (fewer, more) in zip(GridZoom.levels, GridZoom.levels.dropFirst()) {
            #expect((more - fewer) % 2 == 0)
        }
    }

    @Test func aPinchHeadsToTheNextLevelEitherWay() {
        // 5 columns drawn at 1.4× look like 3.6 columns.
        #expect(GridZoom.level(toward: 5 / 1.4, from: 5) == 3)
        #expect(GridZoom.level(toward: 5 / 0.7, from: 5) == 15)
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
        #expect(GridZoom.nearestLevel(to: 8) == 5)
        #expect(GridZoom.nearestLevel(to: 20) == 15)
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
        let stretched = GridZoom.rubberBand(2, limits: GridZoom.scaleLimits(for: 3))
        #expect(stretched > 1 && stretched < 1.5)
        let squeezed = GridZoom.rubberBand(0.5, limits: GridZoom.scaleLimits(for: 15))
        #expect(squeezed < 1 && squeezed > 0.8)
    }

    @Test func aPinchBetweenPhotosAnchorsOnTheNearestOne() {
        let frames = TileFrames()
        let screen = CGRect(x: 0, y: 0, width: 400, height: 800)
        frames.set(CGRect(x: 0, y: 48, width: 60, height: 60), for: 0, columns: 6)
        frames.set(CGRect(x: 64, y: 48, width: 60, height: 60), for: 1, columns: 6)
        // In the gutter, nearer the second photo; above the first row, over the month header.
        #expect(frames.index(at: CGPoint(x: 62.5, y: 70), columns: 6) == nil)
        #expect(frames.index(nearest: CGPoint(x: 62.5, y: 70), columns: 6, within: screen) == 1)
        #expect(frames.index(nearest: CGPoint(x: 10, y: 20), columns: 6, within: screen) == 0)
    }

    @Test func framesFromAnotherLevelOrOffScreenAreIgnored() {
        let frames = TileFrames()
        let screen = CGRect(x: 0, y: 0, width: 400, height: 800)
        frames.set(CGRect(x: 0, y: 48, width: 90, height: 90), for: 0, columns: 4)
        frames.set(CGRect(x: 0, y: 5000, width: 60, height: 60), for: 7, columns: 6)
        #expect(frames.frame(of: 0, columns: 6) == nil)
        #expect(frames.index(nearest: CGPoint(x: 10, y: 60), columns: 6, within: screen) == nil)
        #expect(frames.index(nearest: CGPoint(x: 10, y: 60), columns: 4, within: screen) == 0)
    }
}
