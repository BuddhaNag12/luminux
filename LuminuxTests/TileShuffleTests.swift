import Testing
@testable import Luminux

struct TileShuffleTests {
    @Test func oneSlotChangesAtATime() {
        let steps = TileShuffle.steps(pool: Array(0..<12), slots: 4, count: 60)
        #expect(steps.count == 60)
        for (previous, next) in zip(steps, steps.dropFirst()) {
            let changed = zip(previous.slots, next.slots).filter { $0 != $1 }.count
            #expect(changed == 1)
            #expect(next.changed != previous.changed)
        }
    }

    @Test func aSlotNeverShowsAPhotoAlreadyOnScreen() {
        for step in TileShuffle.steps(pool: Array(0..<12), slots: 4, count: 60) {
            #expect(Set(step.slots).count == 4)
        }
    }

    @Test func aSmallTileChangesEveryStep() {
        let steps = TileShuffle.steps(pool: ["a", "b", "c"], slots: 1, count: 20)
        for (previous, next) in zip(steps, steps.dropFirst()) {
            #expect(previous.slots[0] != next.slots[0])
        }
    }

    @Test func fewerPhotosThanSlotsStillFillsTheTile() {
        let steps = TileShuffle.steps(pool: ["a", "b"], slots: 4, count: 10)
        #expect(steps.allSatisfy { $0.slots.count == 4 })
        #expect(TileShuffle.steps(pool: [Int](), slots: 4, count: 10).isEmpty)
        #expect(TileShuffle.steps(pool: ["only"], slots: 1, count: 5).count == 5)
    }
}
