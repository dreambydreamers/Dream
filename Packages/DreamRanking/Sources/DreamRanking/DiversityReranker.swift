import Foundation

/// Assembles the final feed order from the scored main stream and the
/// deficit-ordered reserved (fairness) stream, enforcing diversity while it
/// walks: creator caps per window, no long same-category runs.
///
/// Production quality is deliberately NOT an input — `hasVideo` and any
/// polish proxy never influence placement, so the feed cannot drift toward
/// polished content.
enum DiversityReranker {

    struct Placed: Equatable {
        let scored: Scored
        let isFairnessSlot: Bool
    }

    /// Greedy assembly. At each position:
    ///   * fairness positions draw from `reserved` (deficit order) while any
    ///     remain — regardless of score;
    ///   * all other positions draw from `main` (score order);
    ///   * within each stream, the first item satisfying the diversity
    ///     constraints is taken — unless a creator/category is "urgent"
    ///     (deferring it further would make the constraint unsatisfiable in
    ///     the remaining positions), in which case the urgent item is drained
    ///     first. If nothing fits at all, the stream head is taken so the walk
    ///     never stalls.
    static func assemble(
        main: [Scored],
        reserved: [Scored],
        config: RankingConfig
    ) -> [Placed] {
        var mainQueue = main
        var reservedQueue = reserved
        var output: [Placed] = []
        var placedCandidates: [DreamCandidate] = []
        let slotPositions = Set(config.fairnessSlotPositions.filter { $0 >= 0 && $0 < config.pageSize })

        while !mainQueue.isEmpty || !reservedQueue.isEmpty {
            let remaining = mainQueue.count + reservedQueue.count
            let positionInPage = config.pageSize > 0 ? output.count % config.pageSize : 0
            let takeReserved = (slotPositions.contains(positionInPage) && !reservedQueue.isEmpty)
                || mainQueue.isEmpty

            if takeReserved {
                let index = pickIndex(from: reservedQueue, placed: placedCandidates,
                                      remaining: remaining, config: config)
                let item = reservedQueue.remove(at: index)
                output.append(Placed(scored: item, isFairnessSlot: true))
                placedCandidates.append(item.candidate)
            } else {
                let index = pickIndex(from: mainQueue, placed: placedCandidates,
                                      remaining: remaining, config: config)
                let item = mainQueue.remove(at: index)
                output.append(Placed(scored: item, isFairnessSlot: false))
                placedCandidates.append(item.candidate)
            }
        }
        return output
    }

    /// Chooses which queued item to place next. Preference order:
    ///   1. among items that keep the constraints intact, an "urgent" one
    ///      (its creator/category supply would otherwise become unplaceable);
    ///   2. otherwise the first fitting item (the queue is already in the
    ///      stream's priority order — score or deficit);
    ///   3. if nothing fits, the head (constraint yields to completeness).
    private static func pickIndex(
        from queue: [Scored],
        placed: [DreamCandidate],
        remaining: Int,
        config: RankingConfig
    ) -> Int {
        guard queue.count > 1 else { return 0 }

        var ownerCounts: [UUID: Int] = [:]
        var categoryCounts: [String: Int] = [:]
        for item in queue {
            ownerCounts[item.candidate.ownerId, default: 0] += 1
            categoryCounts[item.candidate.category, default: 0] += 1
        }

        // Minimum positions a supply of `count` same-keyed items needs, given
        // it may occupy at most `cap` of every `window` positions.
        func pressure(count: Int, cap: Int, window: Int) -> Int {
            guard cap > 0 else { return 0 }
            return count * window / cap
        }
        func urgency(_ candidate: DreamCandidate) -> Int {
            let owner = pressure(
                count: ownerCounts[candidate.ownerId] ?? 0,
                cap: config.maxPerCreatorPerWindow,
                window: config.creatorWindowSize)
            let category = pressure(
                count: categoryCounts[candidate.category] ?? 0,
                cap: config.maxConsecutiveSameCategory,
                window: config.maxConsecutiveSameCategory + 1)
            return max(owner, category)
        }

        var firstFitting: Int?
        var mostUrgent: (index: Int, urgency: Int)?
        for index in queue.indices {
            guard fits(queue[index].candidate, placed: placed, config: config) else { continue }
            if firstFitting == nil { firstFitting = index }
            let value = urgency(queue[index].candidate)
            if value >= remaining, value > (mostUrgent?.urgency ?? Int.min) {
                mostUrgent = (index, value)
            }
        }
        return mostUrgent?.index ?? firstFitting ?? 0
    }

    /// Constraint check for appending `candidate` after `placed`.
    ///
    /// Creator cap: enforced over the trailing window of size
    /// `creatorWindowSize` (checking the trailing window at every append
    /// guarantees, by induction, that EVERY window of that size satisfies the
    /// cap). Category: caps the run of consecutive same-category items.
    static func fits(
        _ candidate: DreamCandidate,
        placed: [DreamCandidate],
        config: RankingConfig
    ) -> Bool {
        if config.maxPerCreatorPerWindow > 0, config.creatorWindowSize > 1 {
            let windowStart = max(0, placed.count - (config.creatorWindowSize - 1))
            let sameCreator = placed[windowStart...]
                .filter { $0.ownerId == candidate.ownerId }.count
            if sameCreator >= config.maxPerCreatorPerWindow { return false }
        }
        if config.maxConsecutiveSameCategory > 0 {
            var run = 0
            for previous in placed.reversed() {
                if previous.category == candidate.category { run += 1 } else { break }
            }
            if run >= config.maxConsecutiveSameCategory { return false }
        }
        return true
    }
}
