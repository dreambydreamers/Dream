import Foundation

// MARK: - DB row DTOs

struct ProfileDTO: Codable, Hashable {
    let id: UUID
    let handle: String?
    let name: String?
    let avatarSeed: Int
    let location: String?
    let skills: [String]

    enum CodingKeys: String, CodingKey {
        case id, handle, name, location, skills
        case avatarSeed = "avatar_seed"
    }
}

struct DreamDTO: Codable, Hashable {
    let id: UUID
    let ownerId: UUID
    let title: String
    let description: String
    let category: String     // dream_category enum, lowercase
    let stage: String        // dream_stage enum, lowercase
    let location: String?
    let helpTags: [String]
    let viewsCount: Int
    let isFeatured: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, description, category, stage, location
        case ownerId = "owner_id"
        case helpTags = "help_tags"
        case viewsCount = "views_count"
        case isFeatured = "is_featured"
        case createdAt = "created_at"
    }
}

struct JourneyStepDTO: Codable, Hashable {
    let id: UUID
    let dreamId: UUID
    let stage: String
    let dateLabel: String
    let note: String
    let done: Bool
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, stage, note, done
        case dreamId = "dream_id"
        case dateLabel = "date_label"
        case sortOrder = "sort_order"
    }
}

struct DreamVideoDTO: Codable, Hashable {
    let id: UUID
    let dreamId: UUID
    let storagePath: String
    let posterPath: String?
    let durationMs: Int?
    let width: Int?
    let height: Int?
    let isPrimary: Bool

    enum CodingKeys: String, CodingKey {
        case id, width, height
        case dreamId = "dream_id"
        case storagePath = "storage_path"
        case posterPath = "poster_path"
        case durationMs = "duration_ms"
        case isPrimary = "is_primary"
    }
}

struct DreamStatsDTO: Codable, Hashable {
    let dreamId: UUID
    let supportersCount: Int
    let offersCount: Int

    enum CodingKeys: String, CodingKey {
        case dreamId = "dream_id"
        case supportersCount = "supporters_count"
        case offersCount = "offers_count"
    }
}

struct ProfileStatsDTO: Codable, Hashable {
    let profileId: UUID
    let videosCount: Int
    let followersCount: Int
    let followingCount: Int
    let offersCount: Int

    enum CodingKeys: String, CodingKey {
        case profileId = "profile_id"
        case videosCount = "videos_count"
        case followersCount = "followers_count"
        case followingCount = "following_count"
        case offersCount = "offers_count"
    }
}

struct HelpOfferDTO: Codable, Hashable {
    let id: UUID
    let dreamId: UUID
    let supporterId: UUID
    let skill: String
    let message: String
    let status: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, skill, message, status
        case dreamId = "dream_id"
        case supporterId = "supporter_id"
        case createdAt = "created_at"
    }
}

// MARK: - Insert payloads

struct NewDreamPayload: Encodable {
    let owner_id: UUID
    let title: String
    let description: String
    let category: String
    let stage: String
    let location: String?
    let help_tags: [String]
}

/// Partial update of the current user's profile (edited fields only).
struct ProfileUpdatePayload: Encodable {
    let name: String?
    let handle: String?
    let location: String?
    let skills: [String]
}

struct FollowPayload: Codable {
    let follower_id: UUID
    let followed_id: UUID
}

struct NewJourneyStepPayload: Encodable {
    let dream_id: UUID
    let stage: String
    let date_label: String
    let note: String
    let done: Bool
    let sort_order: Int
}

struct NewVideoPayload: Encodable {
    let dream_id: UUID
    let storage_path: String
    let poster_path: String?
    let duration_ms: Int?
    let width: Int?
    let height: Int?
    let is_primary: Bool
}

// MARK: - Enum mapping helpers

extension DreamCategory {
    /// DB enum value (lowercase short form). Mirrors the `dream_category` Postgres enum.
    var dbValue: String {
        switch self {
        case .tech: return "tech"
        case .food: return "food"
        case .art: return "art"
        case .impact: return "impact"
        case .education: return "education"
        case .health: return "health"
        case .music: return "music"
        case .sport: return "sport"
        }
    }

    static func from(dbValue raw: String) -> DreamCategory {
        switch raw {
        case "tech": return .tech
        case "food": return .food
        case "art": return .art
        case "impact": return .impact
        case "education": return .education
        case "health": return .health
        case "music": return .music
        case "sport": return .sport
        default: return .tech
        }
    }
}

extension DreamStage {
    var dbValue: String {
        switch self {
        case .idea: return "idea"
        case .early: return "early"
        case .needs: return "needs"
        case .almost: return "almost"
        }
    }

    static func from(dbValue raw: String) -> DreamStage {
        switch raw {
        case "idea": return .idea
        case "early": return .early
        case "needs": return .needs
        case "almost": return .almost
        default: return .idea
        }
    }
}
