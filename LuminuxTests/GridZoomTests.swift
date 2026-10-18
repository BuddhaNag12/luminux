import CoreGraphics
import Testing
@testable import Luminux

struct GridZoomTests {
    @Test func aPinchHeadsToTheNextLevelEitherWay() {
        // 4 columns drawn at 1.4× look like 2.9 columns.
        #expect(GridZoom.level(toward: 4 / 1.4, from: 4) == 3)
        #expect(GridZoom.level(toward: 4 / 0.7, from: 4) == 6)
        // One level per pinch, however far it goes.
        #expect(GridZoom.level(toward: 4 / 0.3, from: 4) == 6)
        #expect(GridZoom.level(toward: 4, from: 4) == nil)
        #expect(GridZoom.level(toward: 1, from: 2) == nil)
        #expect(GridZoom.level(toward: 20, from: 8) == nil)
    }

    @Test func progressIsHalfwayAtTheLogMidpoint() {
        #expect(GridZoom.progress(4, from: 4, to: 6) == 0)
        #expect(GridZoom.progress(6, from: 4, to: 6) == 1)
        #expect(abs(GridZoom.progress(sqrt(24), from: 4, to: 6) - 0.5) < 0.001)
        #expect(GridZoom.progress(4.3, from: 4, to: 6) < 0.5)
        #expect(GridZoom.progress(9, from: 4, to: 6) == 1)
        // Pinching the other way counts from the same start.
        #expect(abs(GridZoom.progress(sqrt(12), from: 4, to: 3) - 0.5) < 0.001)
    }

    @Test func oddColumnCountsSnapToALevel() {
        #expect(GridZoom.nearestLevel(to: 5) == 4)
        #expect(GridZoom.nearestLevel(to: 20) == 8)
    }

    @Test func theGridScalesFreelyToTheLevelsEitherSide() {
        let limits = GridZoom.scaleLimits(for: 4)
        #expect(abs(limits.lowerBound - 4.0 / 6) < 0.001 && abs(limits.upperBound - 4.0 / 3) < 0.001)
        #expect(GridZoom.rubberBand(1.2, limits: limits) == 1.2)
        #expect(GridZoom.rubberBand(0.7, limits: limits) == 0.7)
    }

    @Test func pastTheNextLevelsTheGridResists() {
        let limits = GridZoom.scaleLimits(for: 2)
        let stretched = GridZoom.rubberBand(3, limits: limits)
        #expect(stretched > 1 && stretched < 1.5)
        let squeezed = GridZoom.rubberBand(0.1, limits: GridZoom.scaleLimits(for: 8))
        #expect(squeezed < 1 && squeezed > 0.6)
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
