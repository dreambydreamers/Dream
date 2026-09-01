import XCTest
@testable import DreamRanking

final class SevenDaySimulationTests: XCTestCase {

    /// REQUIRED: every dream meets the exposure floor in a simulated 7-day
    /// run. 150 dreams with long-tail offer distribution, 80 viewers with
    /// varied capability profiles, one session per viewer per day browsing 20
    /// cards — through the real ranker AND the production serving path
    /// (50-item queue draws, refill-below-threshold, unserved-tail dedupe,
    /// impressions only for browsed cards).
    func testEveryDreamReachesExposureFloorWithinSevenDays() {
        let config = RankingConfig.default
        let allTypes: [HelpType] = [.code, .design, .funding, .mentorship,
                                    .marketing, .legal, .space, .other]
        let categories = ["tech", "food", "art", "impact", "education", "health", "music", "sport"]
        let stages = ["idea", "early", "needs", "almost"]

        // 150 dreams: each needs 1–2 help types, ages spread over 20 days.
        var dreams: [FeedSimulation.SimDream] = []
        for index in 0..<150 {
            let primary = allTypes[index % allTypes.count]
            let secondary = allTypes[(index + 3) % allTypes.count]
            dreams.append(.init(
                id: uuid(index),
                ownerId: uuid(10_000 + index),
                category: categories[index % categories.count],
                stage: stages[index % stages.count],
                location: index % 4 == 0 ? "Zagreb" : "Berlin",
                helpTags: [primary.rawValue, secondary.rawValue],
                helpTypes: index % 3 == 0 ? [primary] : [primary, secondary],
                createdAt: daysAgo(Double(index % 20), from: testNow)
            ))
        }

        // 80 viewers: each offers 3 help types (round-robin so every type has
        // ~30 potential helpers), half localized, varied interests.
        var viewers: [ViewerProfile] = []
        for index in 0..<80 {
            viewers.append(makeViewer(
                id: 20_000 + index,
                helpTypesOffered: [
                    allTypes[index % allTypes.count],
                    allTypes[(index + 1) % allTypes.count],
                    allTypes[(index + 2) % allTypes.count],
                ],
                location: index % 2 == 0 ? "Zagreb" : "Berlin",
                categoriesOfInterest: [categories[index % categories.count]]
            ))
        }

        let sim = FeedSimulation(config: config, now: testNow, dreams: dreams, viewers: viewers)

        // Long tail: a popular few soak up offers before the window starts.
        for index in 0..<15 {
            for offer in 0..<5 {
                sim.recordOffer(viewer: uuid(20_000 + offer), dream: uuid(index * 10 % 150))
            }
        }

        for _ in 0..<7 { // days
            for viewerIndex in viewers.indices { // one session per viewer per day
                let browsed = sim.serveSession(toViewerAt: viewerIndex, browsing: 20)
                // Light engagement so affinities move like real usage:
                // complete the first matching item, skip the last item.
                if let match = browsed.first(where: { !$0.candidate.helpTypes.intersection(viewers[viewerIndex].helpTypesOffered).isEmpty }) {
                    sim.recordComplete(viewer: viewers[viewerIndex].userId, dream: match.id)
                }
                if let last = browsed.last {
                    sim.recordSkip(viewer: viewers[viewerIndex].userId, dream: last.id)
                }
            }
            sim.advance(days: 1)
        }

        // Every dream reaches the floor of distinct viewers.
        var starved: [(UUID, Int)] = []
        for dream in dreams {
            let reach = sim.distinctViewers[dream.id]?.count ?? 0
            if reach < config.exposureViewerFloor {
                starved.append((dream.id, reach))
            }
        }
        XCTAssertTrue(
            starved.isEmpty,
            "dreams below the \(config.exposureViewerFloor)-viewer floor after 7 days: \(starved)"
        )

        // And fairness slots were actually browsed at roughly the reserved
        // share (2 of every 10 positions) while under-exposed supply lasted.
        let fairnessShare = Double(sim.fairnessItemsBrowsed) / Double(max(sim.itemsBrowsed, 1))
        XCTAssertGreaterThan(fairnessShare, 0.02, "fairness slots never engaged")
        XCTAssertLessThanOrEqual(fairnessShare, 0.25,
                                 "fairness share should not exceed the reserved ratio by much")
    }

    /// Offers concentrate early on popular dreams, but the under-served boost
    /// + fairness slots keep zero-offer dreams visible: their average reach
    /// must not trail far behind the popular cohort.
    func testZeroOfferDreamsAreNotBuriedRelativeToPopularOnes() {
        let config = RankingConfig.default
        var dreams: [FeedSimulation.SimDream] = []
        for index in 0..<60 {
            dreams.append(.init(
                id: uuid(index), ownerId: uuid(10_000 + index),
                category: ["tech", "art", "food"][index % 3], stage: "early",
                location: nil, helpTags: ["Coding"], helpTypes: [.code],
                createdAt: daysAgo(10)
            ))
        }
        var viewers: [ViewerProfile] = []
        for index in 0..<40 {
            viewers.append(makeViewer(id: 20_000 + index, helpTypesOffered: [.code]))
        }
        let sim = FeedSimulation(config: config, now: testNow, dreams: dreams, viewers: viewers)

        // First 20 dreams are "popular": 5 offers each. Last 40 have zero.
        for index in 0..<20 {
            for offer in 0..<5 {
                sim.recordOffer(viewer: uuid(20_000 + offer), dream: uuid(index))
            }
        }

        for _ in 0..<7 {
            for viewerIndex in viewers.indices {
                sim.serveSession(toViewerAt: viewerIndex, browsing: 10)
            }
            sim.advance(days: 1)
        }

        func averageReach(_ range: Range<Int>) -> Double {
            let total = range.reduce(0) { $0 + (sim.distinctViewers[uuid($1)]?.count ?? 0) }
            return Double(total) / Double(range.count)
        }
        let popularReach = averageReach(0..<20)
        let starvedReach = averageReach(20..<60)
        XCTAssertGreaterThanOrEqual(
            starvedReach, popularReach,
            "zero-offer dreams should reach at least as many viewers as already-supported ones"
        )
    }
}
