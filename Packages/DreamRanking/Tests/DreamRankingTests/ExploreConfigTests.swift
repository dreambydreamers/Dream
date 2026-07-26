import XCTest
@testable import DreamRanking

/// Pins the character of the `.explore` preset relative to `.default`:
/// Explore is fresh + interest-first; Discover is capability-matching-first.
/// The same candidates must invert their ordering between the two configs.
final class ExploreConfigTests: XCTestCase {

    /// A fresh no-match dream vs. an older, well-supported capability match.
    /// Explore surfaces the fresh one; Discover surfaces the match.
    func testFreshOutranksOldMatchOnlyUnderExplore() {
        let viewer = makeViewer(helpTypesOffered: [.code])
        // Fresh, nothing in common with the viewer. Well-exposed so the
        // fairness pass can't reorder; sourced via 'fresh'.
        let fresh = makeCandidate(
            id: 1, owner: 101, category: "food",
            helpTags: ["Legal"], helpTypes: [.legal],
            createdAt: daysAgo(1),
            sources: [.fresh]
        )
        // 20 days old, matches the viewer's capability, already supported
        // (3 offers = boost fully decayed).
        let oldMatch = makeCandidate(
            id: 2, owner: 102, category: "tech",
            createdAt: daysAgo(20), offersReceived: 3
        )

        let explore = DreamRanker.rank(
            candidates: [oldMatch, fresh], viewer: viewer, config: .explore, now: testNow)
        XCTAssertEqual(explore.first?.id, fresh.id,
                       "explore leads with fresh content")

        let discover = DreamRanker.rank(
            candidates: [oldMatch, fresh], viewer: viewer, config: .default, now: testNow)
        XCTAssertEqual(discover.first?.id, oldMatch.id,
                       "discover leads with the capability match")
    }

    /// A strong-interest dream vs. a single capability match, all else equal.
    /// Explore favors the interest; Discover favors the match.
    func testInterestOutranksMatchOnlyUnderExplore() {
        let viewer = makeViewer(
            helpTypesOffered: [.code],
            categoryAffinity: ["art": 1.0]
        )
        let interest = makeCandidate(
            id: 1, owner: 101, category: "art",
            helpTags: ["Legal"], helpTypes: [.legal],
            offersReceived: 3,
            sources: [.categoryAffinity]
        )
        let match = makeCandidate(
            id: 2, owner: 102, category: "tech",
            offersReceived: 3
        )

        let explore = DreamRanker.rank(
            candidates: [match, interest], viewer: viewer, config: .explore, now: testNow)
        XCTAssertEqual(explore.first?.id, interest.id,
                       "explore follows the viewer's interests")

        let discover = DreamRanker.rank(
            candidates: [match, interest], viewer: viewer, config: .default, now: testNow)
        XCTAssertEqual(discover.first?.id, match.id,
                       "discover follows capability")
    }

    /// The fairness invariants are preset-independent: reserved positions
    /// still hold under-exposed dreams by deficit under `.explore`.
    func testFairnessSlotsHoldUnderExploreConfig() {
        let viewer = makeViewer(helpTypesOffered: [.code])
        var pool: [DreamCandidate] = []
        for index in 0..<24 {
            pool.append(makeCandidate(
                id: index, owner: 200 + index,
                category: ["tech", "art", "food"][index % 3]
            ))
        }
        for index in 0..<4 {
            pool.append(makeCandidate(
                id: 100 + index, owner: 300 + index, category: "health",
                helpTags: ["Legal"], helpTypes: [.legal],
                createdAt: daysAgo(10 + Double(index)),
                impressions: index, distinctViewers: index,
                sources: [.underexposed]
            ))
        }

        let config = RankingConfig.explore
        let ranked = DreamRanker.rank(candidates: pool, viewer: viewer, config: config, now: testNow)

        for slot in config.fairnessSlotPositions {
            XCTAssertTrue(ranked[slot].isFairnessSlot)
            XCTAssertLessThan(ranked[slot].candidate.distinctViewers, config.exposureViewerFloor)
        }
        XCTAssertEqual(ranked[config.fairnessSlotPositions[0]].id, uuid(100),
                       "most-starved dream takes the first reserved slot")
    }

    /// Diversity constraints hold under `.explore` too.
    func testDiversityHoldsUnderExploreConfig() {
        let viewer = makeViewer(helpTypesOffered: [.code])
        var pool: [DreamCandidate] = []
        for creator in 0..<10 {
            for item in 0..<3 {
                pool.append(makeCandidate(
                    id: creator * 10 + item,
                    owner: 500 + creator,
                    category: ["tech", "art", "food", "music", "health"][creator % 5],
                    createdAt: daysAgo(Double(creator) + Double(item) * 0.1)
                ))
            }
        }
        let config = RankingConfig.explore
        let ranked = DreamRanker.rank(candidates: pool, viewer: viewer, config: config, now: testNow)

        let owners = ranked.map(\.candidate.ownerId)
        for windowStart in 0...(owners.count - config.creatorWindowSize) {
            let window = owners[windowStart..<(windowStart + config.creatorWindowSize)]
            let counts = Dictionary(grouping: window, by: { $0 }).mapValues(\.count)
            for count in counts.values {
                XCTAssertLessThanOrEqual(count, config.maxPerCreatorPerWindow)
            }
        }
    }
}
