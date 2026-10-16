import Testing
@testable import Luminux

struct LiveTileSchedulerTests {
    @Test func countsEachTimeTheTilesComeBack() {
        let scheduler = LiveTileScheduler()
        scheduler.isPaused = true
        scheduler.isPaused = false
        scheduler.isPaused = false
        #expect(scheduler.returns == 1)
        scheduler.isPaused = true
        scheduler.isPaused = false
        #expect(scheduler.returns == 2)
    }
}
