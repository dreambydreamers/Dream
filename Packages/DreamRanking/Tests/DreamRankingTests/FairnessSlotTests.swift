import XCTest
@testable import DreamRanking

final class FairnessSlotTests: XCTestCase {

    let config = RankingConfig.default
    let viewer = makeViewer(helpTypesOffered: [.code])

    /// Well-exposed high scorers + a few starved low scorers: the reserved
    /// positions of each page must hold the starved dreams even though their
    /// quality score is the lowest in the pool.
    func testReservedPositionsHoldUnderexposedDreamsRegardlessOfScore() {
        var pool: [DreamCandidate] = []
        // 24 well-exposed dreams that match the viewer strongly.
        for index in 0..<24 {
            pool.append(makeCandidate(
                id: index, owner: 200 + index, category: ["tech", "art", "food"][index % 3]
            ))
        }
        // 4 starved dreams with NO match for this viewer (lowest possible score).
        for index in 0..<4 {
            pool.append(makeCandidate(
                id: 100 + index, owner: 300 + index, category: "health",
                helpTags: ["Legal"], helpTypes: [.legal],
                createdAt: daysAgo(10 + Double(index)),
                impressions: index, distinctViewers: index,
                sources: [.underexposed]
            ))
        }

        let ranked = DreamRanker.rank(candidates: pool, viewer: viewer, config: config, now: testNow)

        for slot in config.fairnessSlotPositions {
            XCTAssertTrue(ranked[slot].isFairnessSlot,
                          "position \(slot) of page 1 is reserved for fairness")
            XCTAssertLessThan(ranked[slot].candidate.distinctViewers, config.exposureViewerFloor)
        }
        // Deficit order: the most-starved dream (0 distinct viewers) occupies
        // the first reserved position.
        XCTAssertEqual(ranked[config.fairnessSlotPositions[0]].id, uuid(100))
        XCTAssertEqual(ranked[config.fairnessSlotPositions[1]].id, uuid(101))
    }

    /// When the whole catalog is under-exposed (young app), the reserved pool
    /// is capped at the slots the feed can consume — the rest of the feed
    /// stays score-ordered instead of collapsing into deficit order.
    func testReservedPoolIsCappedWhenEverythingIsUnderexposed() {
        var pool: [DreamCandidate] = []
        for index in 0..<30 {
            // Constructed so diversity constraints never bind (unique owners,
            // period-5 category cycle, strictly monotonic scores): any
            // reordering observed comes from fairness slotting alone.
            pool.append(makeCandidate(
                id: index, owner: 200 + index,
                category: ["tech", "art", "food", "music", "health"][index % 5],
                createdAt: daysAgo(3 + Double(index) * 0.3),
                impressions: index, distinctViewers: index % 20,
                sources: [.helpTypeMatch, .underexposed]
            ))
        }

        let ranked = DreamRanker.rank(candidates: pool, viewer: viewer, config: config, now: testNow)

        let expectedSlots = FairnessPass.slotCount(forFeedLength: pool.count, config: config)
        XCTAssertEqual(ranked.filter(\.isFairnessSlot).count, expectedSlots)

        // Non-fairness items keep descending score order.
        let mainScores = ranked.filter { !$0.isFairnessSlot }.map(\.score.total)
        XCTAssertEqual(mainScores, mainScores.sorted(by: >))
    }

    /// Fairness items still pass the standard exclusions — the pass reserves
    /// slots, it does not resurrect dismissed/own/seen dreams (those never
    /// reach the ranker; here we check the ranker-side defenses hold for
    /// underexposed-sourced rows too).
    func testFairnessPoolStillRespectsEligibility() {
        let ownStarved = makeCandidate(
            id: 1, owner: 1, distinctViewers: 0, sources: [.underexposed]
        ) // owner == viewer
        let ranked = DreamRanker.rank(
            candidates: [ownStarved], viewer: makeViewer(id: 1), config: config, now: testNow
        )
        XCTAssertTrue(ranked.isEmpty)
    }
}
