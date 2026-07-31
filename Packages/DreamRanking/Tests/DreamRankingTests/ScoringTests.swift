import XCTest
@testable import DreamRanking

final class ScoringTests: XCTestCase {

    let config = RankingConfig.default
    let viewer = makeViewer(helpTypesOffered: [.code])

    /// REQUIRED: an under-supported dream outranks a heavily-supported one
    /// when all other signals are equal.
    func testUnderSupportedOutranksWellSupportedCeterisParibus() {
        let starved = makeCandidate(id: 1, owner: 101, offersReceived: 0)
        let popular = makeCandidate(id: 2, owner: 102, offersReceived: 5)

        let ranked = DreamRanker.rank(
            candidates: [popular, starved], viewer: viewer, config: config, now: testNow
        )

        XCTAssertEqual(ranked.first?.id, starved.id,
                       "zero-offer dream must rank first when everything else is equal")
        let starvedScore = ranked.first { $0.id == starved.id }!.score
        let popularScore = ranked.first { $0.id == popular.id }!.score
        XCTAssertGreaterThan(starvedScore.underServedBoost, 0)
        XCTAssertEqual(popularScore.underServedBoost, 0,
                       "5 offers is past saturation (3) — boost fully decayed")
    }

    /// The boost grows as the dream ages while offers stay low.
    func testBoostGrowsWithAgeWhileOffersStayLow() {
        let young = Scoring.score(
            makeCandidate(id: 1, createdAt: daysAgo(3)), viewer: viewer, config: config, now: testNow)
        let old = Scoring.score(
            makeCandidate(id: 2, createdAt: daysAgo(10)), viewer: viewer, config: config, now: testNow)
        let fullyRamped = Scoring.score(
            makeCandidate(id: 3, createdAt: daysAgo(30)), viewer: viewer, config: config, now: testNow)

        XCTAssertGreaterThan(old.underServedBoost, young.underServedBoost)
        XCTAssertEqual(fullyRamped.underServedBoost, config.underServedMaxBoost, accuracy: 0.0001,
                       "boost caps at max after the ramp window")
    }

    /// Popular dreams are never suppressed: the boost only adds, and a
    /// well-supported dream keeps its full base score.
    func testWellSupportedDreamIsNeverSuppressed() {
        let base = makeCandidate(id: 1, offersReceived: 0)
        var popular = base
        popular.offersReceived = 50

        let baseScore = Scoring.score(base, viewer: viewer, config: config, now: testNow)
        let popularScore = Scoring.score(popular, viewer: viewer, config: config, now: testNow)

        XCTAssertGreaterThanOrEqual(popularScore.underServedBoost, 0, "boost never goes negative")
        // Every non-boost component identical — popularity costs nothing.
        XCTAssertEqual(popularScore.helpTypeOverlap, baseScore.helpTypeOverlap)
        XCTAssertEqual(popularScore.skillOverlap, baseScore.skillOverlap)
        XCTAssertEqual(popularScore.categoryAffinity, baseScore.categoryAffinity)
        XCTAssertEqual(popularScore.geoProximity, baseScore.geoProximity)
        XCTAssertEqual(popularScore.stageMatch, baseScore.stageMatch)
        XCTAssertEqual(popularScore.recency, baseScore.recency)
    }

    /// Help-type overlap dominates: a matching dream with nothing else beats a
    /// non-matching dream with every secondary signal in its favor.
    func testHelpTypeOverlapIsHeaviestSignal() {
        let viewer = makeViewer(
            helpTypesOffered: [.funding],
            location: "berlin",
            categoriesOfInterest: ["art"],
            preferredStages: ["idea"]
        )
        let match = makeCandidate(
            id: 1, category: "tech", stage: "almost", helpTags: ["Funding"], helpTypes: [.funding],
            offersReceived: 3 // no under-served boost either
        )
        let secondaries = makeCandidate(
            id: 2, category: "art", stage: "idea", location: "Berlin",
            helpTags: ["Coding"], helpTypes: [.code],
            offersReceived: 3,
            sources: [.categoryAffinity, .geo]
        )

        let matchScore = Scoring.score(match, viewer: viewer, config: config, now: testNow)
        let secondaryScore = Scoring.score(secondaries, viewer: viewer, config: config, now: testNow)
        XCTAssertGreaterThan(matchScore.total, secondaryScore.total,
                             "capability match must outweigh stacked secondary signals")
    }

    /// Production quality is not a signal: identical candidates with and
    /// without video score identically.
    func testLowProductionQualityIsNotPenalized() {
        let polished = makeCandidate(id: 1, hasVideo: true)
        var raw = polished
        raw.hasVideo = false

        let polishedScore = Scoring.score(polished, viewer: viewer, config: config, now: testNow)
        let rawScore = Scoring.score(raw, viewer: viewer, config: config, now: testNow)
        XCTAssertEqual(polishedScore, rawScore)
    }

    func testStageAndGeoAndSkillComponents() {
        let viewer = makeViewer(
            helpTypesOffered: [.code],
            skills: ["iOS Development", "figma"],
            location: "Zagreb",
            preferredStages: ["early"]
        )
        let candidate = makeCandidate(
            id: 1, stage: "early", location: "  zagreb ",
            helpTags: ["iOS development", "Design"], helpTypes: [.code, .design]
        )
        let score = Scoring.score(candidate, viewer: viewer, config: config, now: testNow)

        XCTAssertEqual(score.skillOverlap, config.skillOverlapWeight, "one literal skill-tag match")
        XCTAssertEqual(score.geoProximity, config.geoMatchWeight, "normalized location match")
        XCTAssertEqual(score.stageMatch, config.stagePreferenceWeight)
        XCTAssertEqual(score.helpTypeOverlap, config.helpTypeMatchWeight, "one matched help type")
    }
}
