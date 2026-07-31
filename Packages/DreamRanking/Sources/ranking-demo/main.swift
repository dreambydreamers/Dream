import DreamRanking
import Foundation

// Feeds real RPC output through the real ranker so a feed can be inspected
// without the app. Expects two JSON files: the array returned by
// `get_feed_candidates` and the row array from `get_viewer_ranking_profile`.

struct CandidateRow: Decodable {
    let dream_id: UUID
    let owner_id: UUID
    let title: String
    let category: String
    let stage: String
    let location: String?
    let help_tags: [String]
    let help_types: [String]
    let created_at: Date
    let offers_count: Int
    let supporters_count: Int
    let impressions: Int
    let distinct_viewers: Int
    let is_followed_owner: Bool
    let has_video: Bool
    let sources: [String]

    var candidate: DreamCandidate {
        DreamCandidate(
            id: dream_id, ownerId: owner_id, title: title, category: category,
            stage: stage, location: location, helpTags: help_tags,
            helpTypes: Set(help_types.compactMap(HelpType.init(rawValue:))),
            createdAt: created_at, offersReceived: offers_count,
            supportersCount: supporters_count, impressions: impressions,
            distinctViewers: distinct_viewers, isFollowedOwner: is_followed_owner,
            hasVideo: has_video,
            sources: Set(sources.compactMap(CandidateSource.init(rawValue:)))
        )
    }
}

struct ProfileRow: Decodable {
    let user_id: UUID
    let skills: [String]
    let location: String?
    let help_types: [String]
    let weekly_capacity_hours: Int
    let categories_of_interest: [String]
    let preferred_stages: [String]
    let followed_owner_ids: [UUID]
    let category_affinity: [String: Double]

    var viewer: ViewerProfile {
        ViewerProfile(
            userId: user_id,
            helpTypesOffered: Set(help_types.map(HelpType.normalize)),
            skills: Set(skills),
            location: location,
            weeklyCapacityHours: weekly_capacity_hours,
            categoriesOfInterest: Set(categories_of_interest),
            preferredStages: Set(preferred_stages),
            categoryAffinity: category_affinity,
            followedOwnerIds: Set(followed_owner_ids)
        )
    }
}

func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plain = ISO8601DateFormatter()
    decoder.dateDecodingStrategy = .custom { d in
        let raw = try d.singleValueContainer().decode(String.self)
        if let date = fractional.date(from: raw) ?? plain.date(from: raw) { return date }
        throw DecodingError.dataCorrupted(.init(
            codingPath: d.codingPath, debugDescription: "Unparseable date: \(raw)"))
    }
    return decoder
}

guard CommandLine.arguments.count == 3 else {
    print("usage: ranking-demo <candidates.json> <profile.json>")
    exit(1)
}

do {
    let decoder = makeDecoder()
    let candidateData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    let profileData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
    let candidates = try decoder.decode([CandidateRow].self, from: candidateData).map(\.candidate)
    guard let profile = try decoder.decode([ProfileRow].self, from: profileData).first else {
        print("profile.json contained no rows"); exit(1)
    }
    let viewer = profile.viewer

    let ranked = DreamRanker.rank(
        candidates: candidates, viewer: viewer, config: .default, now: Date()
    )

    print("Viewer \(viewer.userId)")
    print("  offers: \(viewer.helpTypesOffered.map(\.rawValue).sorted().joined(separator: ", "))")
    print("  skills: \(viewer.skills.sorted().joined(separator: ", "))")
    print("  location: \(viewer.location ?? "—")  affinity: \(viewer.categoryAffinity)")
    print("\n#   score  F  dream                                    reason")
    for (index, item) in ranked.enumerated() {
        let flag = item.isFairnessSlot ? "◆" : " "
        let title = item.candidate.title.padding(toLength: 40, withPad: " ", startingAt: 0)
        let score = String(format: "%5.2f", item.score.total)
        print("\(String(format: "%3d", index + 1)) \(score)  \(flag)  \(title) \(item.reason)")
    }

    let fairnessCount = ranked.filter(\.isFairnessSlot).count
    print("\n\(ranked.count) items, \(fairnessCount) fairness slots")
} catch {
    print("ranking-demo failed: \(error)")
    exit(1)
}
