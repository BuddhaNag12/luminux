import Testing
@testable import Luminux

struct GridZoomTests {
    @Test func pinchingOutShowsFewerBiggerPhotos() {
        #expect(GridZoom.columns(after: 4, magnification: 1.4) == 3)
        #expect(GridZoom.columns(after: 4, magnification: 2.5) == 2)
    }

    @Test func pinchingInShowsMorePhotos() {
        #expect(GridZoom.columns(after: 4, magnification: 0.7) == 6)
        #expect(GridZoom.columns(after: 4, magnification: 0.4) == 8)
    }

    @Test func smallPinchesAndTheEndsStayPut() {
        #expect(GridZoom.columns(after: 4, magnification: 1.1) == 4)
        #expect(GridZoom.columns(after: 2, magnification: 3) == 2)
        #expect(GridZoom.columns(after: 8, magnification: 0.3) == 8)
    }

    @Test func oddColumnCountsSnapToALevel() {
        #expect(GridZoom.nearestLevel(to: 5) == 4)
        #expect(GridZoom.nearestLevel(to: 20) == 8)
    }
}
