import XCTest
@testable import DreamRanking

final class DiversityTests: XCTestCase {

    let config = RankingConfig.default
    let viewer = makeViewer(helpTypesOffered: [.code])

    /// REQUIRED: the diversity constraints hold on the re-ranked output.
    /// Creator cap: no more than 2 dreams from the same creator in any run of
    /// 10 consecutive items. Category cap: no more than 2 consecutive
    /// same-category items.
    func testCreatorAndCategoryConstraintsHoldOnOutput() {
        var pool: [DreamCandidate] = []
        // 10 creators × 3 dreams each, biased so naive score-order would clump:
        // same-creator dreams share category and near-identical signals.
        for creator in 0..<10 {
            for item in 0..<3 {
                pool.append(makeCandidate(
                    id: creator * 10 + item,
                    owner: 500 + creator,
                    category: ["tech", "art", "food", "music", "health"][creator % 5],
                    helpTypes: creator % 2 == 0 ? [.code] : [.design],
                    createdAt: daysAgo(Double(creator) + Double(item) * 0.1),
                    offersReceived: creator % 4
                ))
            }
        }

        let ranked = DreamRanker.rank(candidates: pool, viewer: viewer, config: config, now: testNow)
        XCTAssertEqual(ranked.count, pool.count, "re-rank never drops items")

        // Sliding creator window.
        let owners = ranked.map(\.candidate.ownerId)
        for windowStart in 0...(owners.count - config.creatorWindowSize) {
            let window = owners[windowStart..<(windowStart + config.creatorWindowSize)]
            let counts = Dictionary(grouping: window, by: { $0 }).mapValues(\.count)
            for (owner, count) in counts {
                XCTAssertLessThanOrEqual(
                    count, config.maxPerCreatorPerWindow,
                    "creator \(owner) appears \(count)× in window starting at \(windowStart)")
            }
        }

        // Category runs.
        var run = 1
        for index in 1..<ranked.count {
            if ranked[index].candidate.category == ranked[index - 1].candidate.category {
                run += 1
            } else {
                run = 1
            }
            XCTAssertLessThanOrEqual(run, config.maxConsecutiveSameCategory,
                                     "category run too long at position \(index)")
        }
    }

    /// Low-production dreams flow through the re-rank unpenalized: flipping
    /// hasVideo changes nothing about placement.
    func testHasVideoDoesNotAffectPlacement() {
        var pool: [DreamCandidate] = []
        for index in 0..<20 {
            pool.append(makeCandidate(
                id: index, owner: 500 + index,
                category: ["tech", "art", "food"][index % 3],
                createdAt: daysAgo(Double(index)),
                hasVideo: index % 2 == 0
            ))
        }
        let ranked = DreamRanker.rank(candidates: pool, viewer: viewer, config: config, now: testNow)

        var flipped = pool
        for index in flipped.indices { flipped[index].hasVideo.toggle() }
        let rankedFlipped = DreamRanker.rank(candidates: flipped, viewer: viewer, config: config, now: testNow)

        XCTAssertEqual(ranked.map(\.id), rankedFlipped.map(\.id),
                       "production quality must not influence order")
        // And videoless dreams actually appear in the output.
        XCTAssertTrue(ranked.contains { !$0.candidate.hasVideo })
    }

    /// Same inputs, same seed → same output (pure function contract).
    func testDeterminism() {
        var pool: [DreamCandidate] = []
        for index in 0..<25 {
            pool.append(makeCandidate(
                id: index, owner: 500 + index % 7,
                category: ["tech", "art"][index % 2],
                offersReceived: index % 3
            ))
        }
        let first = DreamRanker.rank(candidates: pool, viewer: viewer, config: config, now: testNow, seed: 42)
        let second = DreamRanker.rank(candidates: pool, viewer: viewer, config: config, now: testNow, seed: 42)
        XCTAssertEqual(first, second)
    }
}
