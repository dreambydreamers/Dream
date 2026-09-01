import Foundation
@testable import DreamRanking

/// Fixed "now" so every test is deterministic.
let testNow = Date(timeIntervalSince1970: 1_753_000_000)

/// Deterministic UUID from an integer — no randomness anywhere in the tests.
func uuid(_ n: Int) -> UUID {
    let hex = String(format: "%012x", n)
    return UUID(uuidString: "00000000-0000-4000-8000-\(hex)")!
}

func daysAgo(_ days: Double, from reference: Date = testNow) -> Date {
    reference.addingTimeInterval(-days * 86_400)
}

/// A candidate that is, by default, "ordinary": well-exposed (above the
/// exposure floor, so it never qualifies for fairness slots), no offers yet,
/// sourced via help-type match.
func makeCandidate(
    id: Int,
    owner: Int = 1_000,
    title: String = "Test dream",
    category: String = "tech",
    stage: String = "early",
    location: String? = nil,
    helpTags: [String] = ["Coding"],
    helpTypes: Set<HelpType> = [.code],
    createdAt: Date = daysAgo(20),
    offersReceived: Int = 0,
    supportersCount: Int = 0,
    impressions: Int = 500,
    distinctViewers: Int = 100,
    isFollowedOwner: Bool = false,
    hasVideo: Bool = true,
    sources: Set<CandidateSource> = [.helpTypeMatch]
) -> DreamCandidate {
    DreamCandidate(
        id: uuid(id),
        ownerId: uuid(owner),
        title: title,
        category: category,
        stage: stage,
        location: location,
        helpTags: helpTags,
        helpTypes: helpTypes,
        createdAt: createdAt,
        offersReceived: offersReceived,
        supportersCount: supportersCount,
        impressions: impressions,
        distinctViewers: distinctViewers,
        isFollowedOwner: isFollowedOwner,
        hasVideo: hasVideo,
        sources: sources
    )
}

func makeViewer(
    id: Int = 1,
    helpTypesOffered: Set<HelpType> = [.code],
    skills: Set<String> = [],
    location: String? = nil,
    categoriesOfInterest: Set<String> = [],
    preferredStages: Set<String> = [],
    categoryAffinity: [String: Double] = [:],
    followedOwnerIds: Set<UUID> = []
) -> ViewerProfile {
    ViewerProfile(
        userId: uuid(id),
        helpTypesOffered: helpTypesOffered,
        skills: skills,
        location: location,
        categoriesOfInterest: categoriesOfInterest,
        preferredStages: preferredStages,
        categoryAffinity: categoryAffinity,
        followedOwnerIds: followedOwnerIds
    )
}
