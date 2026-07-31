import Foundation

/// The ranking pipeline. Pure by contract: no IO, no clocks except `now`,
/// no randomness except `seed`. (candidates, viewerProfile, config) in,
/// ranked feed with reasons out — fully unit-testable.
///
/// Pipeline order (mirrors the product spec):
///   1. Eligibility filter (defense in depth over the SQL exclusions).
///   2. FAIRNESS PASS FIRST — reserve under-exposed dreams for the fairness
///      slots by exposure deficit, before any quality scoring.
///   3. Score the main stream (help-type overlap heaviest; under-served boost;
///      mild recency).
///   4. Diversity-aware assembly — creator caps, category-run caps, fairness
///      slots injected at reserved positions per page.
///   5. Reason string per item.
public enum DreamRanker {

    public static func rank(
        candidates: [DreamCandidate],
        viewer: ViewerProfile,
        config: RankingConfig = .default,
        now: Date,
        seed: UInt64 = 0
    ) -> [RankedDream] {
        // 1. Eligibility + dedup (merge sources when the same dream arrives twice).
        var byId: [UUID: DreamCandidate] = [:]
        var order: [UUID] = []
        for candidate in candidates {
            guard candidate.ownerId != viewer.userId, !candidate.sources.isEmpty else { continue }
            if var existing = byId[candidate.id] {
                existing.sources.formUnion(candidate.sources)
                byId[candidate.id] = existing
            } else {
                byId[candidate.id] = candidate
                order.append(candidate.id)
            }
        }
        let eligible = order.compactMap { byId[$0] }

        // 2. Fairness pass — before scoring, by deficit, never by score.
        let (reserved, rest) = FairnessPass.selectUnderexposed(eligible, config: config)

        // 3. Score. Reserved items are scored too (for display/telemetry),
        //    but their PLACEMENT ignores the score.
        func scored(_ list: [DreamCandidate]) -> [Scored] {
            list.map { Scored(candidate: $0, breakdown: Scoring.score($0, viewer: viewer, config: config, now: now)) }
        }
        let mainScored = scored(rest).sorted {
            if $0.breakdown.total != $1.breakdown.total {
                return $0.breakdown.total > $1.breakdown.total
            }
            let left = Scoring.tieBreak($0.candidate.id, seed: seed)
            let right = Scoring.tieBreak($1.candidate.id, seed: seed)
            if left != right { return left < right }
            return $0.candidate.id.uuidString < $1.candidate.id.uuidString
        }
        let reservedScored = scored(reserved) // keeps deficit order from the fairness pass

        // 4. Diversity-aware assembly with fairness-slot injection.
        let placed = DiversityReranker.assemble(
            main: mainScored,
            reserved: reservedScored,
            config: config
        )

        // 5. Reasons.
        return placed.map { item in
            RankedDream(
                candidate: item.scored.candidate,
                score: item.scored.breakdown,
                isFairnessSlot: item.isFairnessSlot,
                reason: Reasons.build(
                    for: item.scored.candidate,
                    breakdown: item.scored.breakdown,
                    viewer: viewer,
                    isFairnessSlot: item.isFairnessSlot
                )
            )
        }
    }
}
