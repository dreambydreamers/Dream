import Foundation

/// The fairness pass runs FIRST, before any quality scoring. Its job: make
/// sure dreams below the minimum-exposure floor get reserved feed slots so
/// every dream reaches N relevant viewers within its first days — a dream
/// with zero help offers is a failure of the system, not of the dream.
enum FairnessPass {

    /// Splits candidates into the reserved fairness pool and the rest.
    ///
    /// A candidate qualifies when the server flagged it `underexposed` or its
    /// distinct-viewer count sits below the floor. Qualifiers are ordered by
    /// exposure deficit (fewest distinct viewers first, then oldest first) —
    /// deliberately NOT by score — and the pool is capped at the number of
    /// fairness slots the assembled feed can actually consume. Overflow goes
    /// back to the scored stream (where the under-served boost still applies),
    /// so when most of the catalog is under-exposed the feed stays
    /// score-ordered instead of collapsing into deficit order.
    static func selectUnderexposed(
        _ candidates: [DreamCandidate],
        config: RankingConfig
    ) -> (reserved: [DreamCandidate], rest: [DreamCandidate]) {
        var qualifying: [DreamCandidate] = []
        var rest: [DreamCandidate] = []
        for candidate in candidates {
            if candidate.sources.contains(.underexposed)
                || candidate.distinctViewers < config.exposureViewerFloor {
                qualifying.append(candidate)
            } else {
                rest.append(candidate)
            }
        }
        qualifying.sort {
            if $0.distinctViewers != $1.distinctViewers {
                return $0.distinctViewers < $1.distinctViewers
            }
            if $0.createdAt != $1.createdAt {
                return $0.createdAt < $1.createdAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }

        let slotCapacity = slotCount(forFeedLength: candidates.count, config: config)
        let reserved = Array(qualifying.prefix(slotCapacity))
        rest.append(contentsOf: qualifying.dropFirst(slotCapacity))
        return (reserved, rest)
    }

    /// How many fairness slots a feed of `length` items contains.
    static func slotCount(forFeedLength length: Int, config: RankingConfig) -> Int {
        guard length > 0, config.pageSize > 0 else { return 0 }
        let slotsPerPage = config.fairnessSlotPositions
            .filter { $0 >= 0 && $0 < config.pageSize }.count
        let fullPages = length / config.pageSize
        let remainder = length % config.pageSize
        let partial = config.fairnessSlotPositions
            .filter { $0 >= 0 && $0 < remainder }.count
        return fullPages * slotsPerPage + partial
    }
}
