import XCTest
@testable import DreamRanking

final class CandidateFilterTests: XCTestCase {

    /// REQUIRED: help-type mismatches are excluded from candidates. A dream
    /// whose needs don't intersect the viewer's offers — and that matches no
    /// other source — never enters the pool at all.
    func testHelpTypeMismatchProducesNoCandidate() {
        let viewer = makeViewer(id: 1, helpTypesOffered: [.funding])
        let sim = FeedSimulation(
            now: testNow,
            dreams: [
                .init(id: uuid(10), ownerId: uuid(100), category: "food", stage: "early",
                      location: nil, helpTags: ["Coding"], helpTypes: [.code],
                      createdAt: daysAgo(10)) // not fresh
            ],
            viewers: [viewer]
        )
        // Push the dream over the exposure floor so 'underexposed' can't admit it.
        for viewerIndex in 0..<30 {
            sim.recordView(viewer: uuid(500 + viewerIndex), dream: uuid(10))
        }

        let pool = sim.candidates(for: viewer)
        XCTAssertTrue(pool.isEmpty,
                      "code-only dream must not be a candidate for a funding-only viewer")
    }

    /// The help_type_match source is never attached without a real overlap.
    func testHelpTypeMatchSourceRequiresRealOverlap() {
        let viewer = makeViewer(id: 1, helpTypesOffered: [.funding], categoriesOfInterest: ["food"])
        let sim = FeedSimulation(
            now: testNow,
            dreams: [
                .init(id: uuid(10), ownerId: uuid(100), category: "food", stage: "early",
                      location: nil, helpTags: ["Coding"], helpTypes: [.code],
                      createdAt: daysAgo(10))
            ],
            viewers: [viewer]
        )
        let pool = sim.candidates(for: viewer)
        // Reachable via category interest / underexposed — but never via help-type match.
        for candidate in pool {
            XCTAssertFalse(candidate.sources.contains(.helpTypeMatch))
        }
    }

    /// Defense in depth in the ranker itself: viewer-owned dreams and
    /// sourceless rows are dropped even if the server returned them.
    func testRankerDropsOwnDreamsAndSourcelessRows() {
        let viewer = makeViewer(id: 1)
        let own = makeCandidate(id: 10, owner: 1) // owner == viewer
        let sourceless = makeCandidate(id: 11, sources: [])
        let good = makeCandidate(id: 12)

        let ranked = DreamRanker.rank(
            candidates: [own, sourceless, good], viewer: viewer, config: .default, now: testNow
        )
        XCTAssertEqual(ranked.map(\.id), [good.id])
    }

    /// Seen (within TTL) and dismissed dreams never re-enter the pool.
    func testSeenAndDismissedAreExcluded() {
        let viewer = makeViewer(id: 1, helpTypesOffered: [.code])
        let sim = FeedSimulation(
            now: testNow,
            dreams: [
                .init(id: uuid(10), ownerId: uuid(100), category: "tech", stage: "early",
                      location: nil, helpTags: ["Coding"], helpTypes: [.code], createdAt: daysAgo(5)),
                .init(id: uuid(11), ownerId: uuid(101), category: "tech", stage: "early",
                      location: nil, helpTags: ["Coding"], helpTypes: [.code], createdAt: daysAgo(5)),
                .init(id: uuid(12), ownerId: uuid(102), category: "tech", stage: "early",
                      location: nil, helpTags: ["Coding"], helpTypes: [.code], createdAt: daysAgo(5)),
            ],
            viewers: [viewer]
        )
        sim.recordView(viewer: viewer.userId, dream: uuid(10))
        sim.recordDismiss(viewer: viewer.userId, dream: uuid(11))

        let ids = Set(sim.candidates(for: viewer).map(\.id))
        XCTAssertEqual(ids, [uuid(12)], "seen and dismissed dreams are excluded")
    }

    /// Duplicate rows for the same dream merge their sources instead of
    /// appearing twice.
    func testDuplicateCandidatesMergeSources() {
        let viewer = makeViewer(id: 1)
        let viaHelp = makeCandidate(id: 10, sources: [.helpTypeMatch])
        let viaGeo = makeCandidate(id: 10, sources: [.geo])

        let ranked = DreamRanker.rank(
            candidates: [viaHelp, viaGeo], viewer: viewer, config: .default, now: testNow
        )
        XCTAssertEqual(ranked.count, 1)
        XCTAssertEqual(ranked[0].sources, [.helpTypeMatch, .geo])
    }
}
