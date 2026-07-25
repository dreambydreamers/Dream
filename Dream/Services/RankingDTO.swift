import DreamRanking
import Foundation

// MARK: - Engagement events

/// Client-side engagement event types; raw values match the SQL enum
/// `engagement_event_type`.
enum EngagementEventType: String, Codable, Hashable {
    case view
    case watchProgress = "watch_progress"
    case complete
    case skip
    case offerHelp = "offer_help"
    case comment
    case save
    case share
    case follow
    case notRelevant = "not_relevant"
}

/// One element of the `log_engagement_batch` RPC's `p_events` array.
struct EngagementEventPayload: Codable, Hashable {
    let dreamId: UUID
    let eventType: String
    let watchMs: Int?
    let videoDurationMs: Int?

    enum CodingKeys: String, CodingKey {
        case dreamId = "dream_id"
        case eventType = "event_type"
        case watchMs = "watch_ms"
        case videoDurationMs = "video_duration_ms"
    }

    init(type: EngagementEventType, dreamId: UUID, watchMs: Int? = nil, videoDurationMs: Int? = nil) {
        self.dreamId = dreamId
        self.eventType = type.rawValue
        self.watchMs = watchMs
        self.videoDurationMs = videoDurationMs
    }
}

// MARK: - Viewer ranking profile (RPC get_viewer_ranking_profile)

struct ViewerRankingProfileDTO: Codable {
    let userId: UUID
    let skills: [String]
    let location: String?
    let helpTypes: [String]
    let weeklyCapacityHours: Int
    let categoriesOfInterest: [String]
    let preferredStages: [String]
    let followedOwnerIds: [UUID]
    let categoryAffinity: [String: Double]

    enum CodingKeys: String, CodingKey {
        case skills, location
        case userId = "user_id"
        case helpTypes = "help_types"
        case weeklyCapacityHours = "weekly_capacity_hours"
        case categoriesOfInterest = "categories_of_interest"
        case preferredStages = "preferred_stages"
        case followedOwnerIds = "followed_owner_ids"
        case categoryAffinity = "category_affinity"
    }

    var viewerProfile: ViewerProfile {
        ViewerProfile(
            userId: userId,
            helpTypesOffered: Set(helpTypes.map(HelpType.normalize)),
            skills: Set(skills),
            location: location,
            weeklyCapacityHours: weeklyCapacityHours,
            categoriesOfInterest: Set(categoriesOfInterest),
            preferredStages: Set(preferredStages),
            categoryAffinity: categoryAffinity,
            followedOwnerIds: Set(followedOwnerIds)
        )
    }
}

// MARK: - Feed candidates (RPC get_feed_candidates)

struct FeedCandidateDTO: Codable {
    let dreamId: UUID
    let ownerId: UUID
    let title: String
    let category: String
    let stage: String
    let location: String?
    let helpTags: [String]
    let helpTypes: [String]
    let createdAt: Date
    let offersCount: Int
    let supportersCount: Int
    let impressions: Int
    let distinctViewers: Int
    let isFollowedOwner: Bool
    let hasVideo: Bool
    let sources: [String]

    enum CodingKeys: String, CodingKey {
        case title, category, stage, location, impressions, sources
        case dreamId = "dream_id"
        case ownerId = "owner_id"
        case helpTags = "help_tags"
        case helpTypes = "help_types"
        case createdAt = "created_at"
        case offersCount = "offers_count"
        case supportersCount = "supporters_count"
        case distinctViewers = "distinct_viewers"
        case isFollowedOwner = "is_followed_owner"
        case hasVideo = "has_video"
    }

    var candidate: DreamCandidate {
        DreamCandidate(
            id: dreamId,
            ownerId: ownerId,
            title: title,
            category: category,
            stage: stage,
            location: location,
            helpTags: helpTags,
            helpTypes: Set(helpTypes.compactMap(HelpType.init(rawValue:))),
            createdAt: createdAt,
            offersReceived: offersCount,
            supportersCount: supportersCount,
            impressions: impressions,
            distinctViewers: distinctViewers,
            isFollowedOwner: isFollowedOwner,
            hasVideo: hasVideo,
            sources: Set(sources.compactMap(CandidateSource.init(rawValue:)))
        )
    }
}

// MARK: - Supporter profile upsert payload

struct SupporterProfilePayload: Codable {
    let userId: UUID
    let helpTypes: [String]
    let weeklyCapacityHours: Int
    let categoriesOfInterest: [String]
    let preferredStages: [String]

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case helpTypes = "help_types"
        case weeklyCapacityHours = "weekly_capacity_hours"
        case categoriesOfInterest = "categories_of_interest"
        case preferredStages = "preferred_stages"
    }
}
