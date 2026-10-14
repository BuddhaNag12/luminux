import Foundation

/// The order a photo tile changes in: one slot at a time, never the slot that just changed, with the next photo that
/// isn't already showing, sliding in from a random side.
nonisolated enum TileShuffle {
    enum Side: CaseIterable, Sendable { case top, bottom, leading, trailing }

    struct Step<Photo: Equatable>: Equatable {
        /// What each slot shows.
        var slots: [Photo]
        /// The slot that just changed, nil for the first step.
        var changed: Int?
        var side: Side
        /// How many times each slot has changed, so the newest photo can sit on top while it slides in.
        var generations: [Int]
    }

    static func steps<Photo: Equatable>(pool: [Photo], slots slotCount: Int, count: Int) -> [Step<Photo>] {
        guard !pool.isEmpty, slotCount > 0, count > 0 else { return [] }
        let shuffled = pool.shuffled()
        // With fewer photos than slots, the first ones fill in again.
        var slots = (0..<slotCount).map { shuffled[$0 % shuffled.count] }
        var queue = Array(shuffled.dropFirst(min(slotCount, shuffled.count)))
        var generations = Array(repeating: 0, count: slotCount)
        var steps = [Step(slots: slots, changed: nil, side: .bottom, generations: generations)]
        var last: Int?

        while steps.count < count {
            let choices = (0..<slotCount).filter { $0 != last || slotCount == 1 }
            let slot = choices.randomElement()!
            if queue.isEmpty { queue = pool.shuffled() }
            // Skip photos already on screen when there are others to show.
            let index = queue.firstIndex { !slots.contains($0) } ?? 0
            let photo = queue.remove(at: index)
            guard photo != slots[slot] || pool.count == 1 else { continue }
            queue.append(slots[slot])
            slots[slot] = photo
            generations[slot] += 1
            last = slot
            steps.append(Step(slots: slots, changed: slot, side: Side.allCases.randomElement()!, generations: generations))
        }
        return steps
    }
}
