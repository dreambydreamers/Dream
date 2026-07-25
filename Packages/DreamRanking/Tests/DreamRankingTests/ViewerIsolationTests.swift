import XCTest
@testable import DreamRanking

final class ViewerIsolationTests: XCTestCase {

    /// REQUIRED: repeated fast skips of a dream do not reduce its ranking for
    /// other viewers. Viewer A hammering skip on a dream must leave viewer B's
    /// scores and ordering bit-for-bit identical.
    func testViewerASkipsDoNotChangeViewerBRanking() {
        let viewerA = makeViewer(id: 1, helpTypesOffered: [.code])
        let viewerB = makeViewer(id: 2, helpTypesOffered: [.code])
        var dreams: [FeedSimulation.SimDream] = []
        for index in 0..<12 {
            dreams.append(.init(
                id: uuid(100 + index), ownerId: uuid(1_000 + index),
                category: ["tech", "art", "food"][index % 3], stage: "early",
                location: nil, helpTags: ["Coding"], helpTypes: [.code],
                createdAt: daysAgo(Double(index) + 2)
            ))
        }
        let sim = FeedSimulation(now: testNow, dreams: dreams, viewers: [viewerA, viewerB])
        let target = uuid(100)

        // Baseline ranking for B.
        let before = DreamRanker.rank(
            candidates: sim.candidates(for: viewerB),
            viewer: sim.profileWithAffinity(viewerB),
            config: .default, now: testNow
        )

        // Viewer A sees the dream once, then skips it 50 times.
        sim.recordView(viewer: viewerA.userId, dream: target)
        for _ in 0..<50 {
            sim.recordSkip(viewer: viewerA.userId, dream: target)
        }

        let after = DreamRanker.rank(
            candidates: sim.candidates(for: viewerB),
            viewer: sim.profileWithAffinity(viewerB),
            config: .default, now: testNow
        )

        XCTAssertEqual(before.map(\.id), after.map(\.id),
                       "A's skips must not move the dream for B")
        // Scores identical too — not just ordering.
        for (lhs, rhs) in zip(before, after) {
            XCTAssertEqual(lhs.score, rhs.score,
                           "score for \(lhs.id) changed after another viewer's skips")
        }
    }

    /// The skip DOES lower the skipping viewer's own category affinity —
    /// that's the intended routing effect — while other viewers' profiles
    /// stay untouched.
    func testSkipsAdjustOnlyTheSkippersOwnAffinity() {
        let viewerA = makeViewer(id: 1, helpTypesOffered: [.code])
        let viewerB = makeViewer(id: 2, helpTypesOffered: [.code])
        let sim = FeedSimulation(
            now: testNow,
            dreams: [
                .init(id: uuid(100), ownerId: uuid(1_000), category: "tech", stage: "early",
                      location: nil, helpTags: ["Coding"], helpTypes: [.code], createdAt: daysAgo(5)),
                .init(id: uuid(101), ownerId: uuid(1_001), category: "art", stage: "early",
                      location: nil, helpTags: ["Design"], helpTypes: [.design], createdAt: daysAgo(5)),
            ],
            viewers: [viewerA, viewerB]
        )

        // A completes an art dream (positive) and skips tech repeatedly.
        sim.recordComplete(viewer: viewerA.userId, dream: uuid(101))
        for _ in 0..<10 {
            sim.recordSkip(viewer: viewerA.userId, dream: uuid(100))
        }

        let profileA = sim.profileWithAffinity(viewerA)
        let profileB = sim.profileWithAffinity(viewerB)

        XCTAssertEqual(profileA.categoryAffinity["art"], 1.0)
        XCTAssertEqual(profileA.categoryAffinity["tech"], 0.0,
                       "negative points clamp to zero — skips lower A's own tech affinity")
        XCTAssertTrue(profileB.categoryAffinity.isEmpty,
                      "B's profile is untouched by A's behavior")
    }

    /// Structural guarantee: a viewer's engagement can only reach global state
    /// through impressions/distinct-viewers (exposure bookkeeping) and offer
    /// counts — and scoring ignores exposure fields entirely. Verified by
    /// perturbing them and asserting the breakdown is unchanged.
    func testScoringIgnoresExposureFields() {
        let viewer = makeViewer(id: 1, helpTypesOffered: [.code])
        let base = makeCandidate(id: 1, impressions: 10, distinctViewers: 40)
        var perturbed = base
        perturbed.impressions = 1_000_000
        perturbed.distinctViewers = 99_999

        let baseScore = Scoring.score(base, viewer: viewer, config: .default, now: testNow)
        let perturbedScore = Scoring.score(perturbed, viewer: viewer, config: .default, now: testNow)
        XCTAssertEqual(baseScore, perturbedScore,
                       "exposure counters must never leak into the quality score")
    }
}
