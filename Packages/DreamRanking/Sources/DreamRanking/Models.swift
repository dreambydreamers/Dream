import Foundation

/// Which candidate-generation source(s) surfaced a dream. Raw values match
/// the `sources` strings returned by the `get_feed_candidates` RPC.
public enum CandidateSource: String, Codable, Sendable, Hashable {
    case helpTypeMatch = "help_type_match"
    case skillOverlap = "skill_overlap"
    case categoryAffinity = "category_affinity"
    case geo
    case followed
    case fresh
    case underexposed
    // Future: case embedding — add the SQL CTE and this case; nothing else changes.
}

/// Everything the ranker knows about the viewer. Watch signals live ONLY here
/// (`categoryAffinity`) — they route dreams to the right viewers and never
/// feed back into a dream's global standing.
public struct ViewerProfile: Sendable, Equatable {
    public var userId: UUID
    public var helpTypesOffered: Set<HelpType>
    /// Lowercased/trimmed on init.
    public var skills: Set<String>
    /// Lowercased/trimmed on init; nil when unset.
    public var location: String?
    public var weeklyCapacityHours: Int
    /// dream_category raw values ("tech", "food", …).
    public var categoriesOfInterest: Set<String>
    /// dream_stage raw values ("idea", "early", "needs", "almost").
    public var preferredStages: Set<String>
    /// Learned from the viewer's own engagement, values in [0, 1].
    public var categoryAffinity: [String: Double]
    public var followedOwnerIds: Set<UUID>

    public init(
        userId: UUID,
        helpTypesOffered: Set<HelpType> = [],
        skills: Set<String> = [],
        location: String? = nil,
        weeklyCapacityHours: Int = 2,
        categoriesOfInterest: Set<String> = [],
        preferredStages: Set<String> = [],
        categoryAffinity: [String: Double] = [:],
        followedOwnerIds: Set<UUID> = []
    ) {
        self.userId = userId
        self.helpTypesOffered = helpTypesOffered
        self.skills = Set(skills.map(Normalize.token).filter { !$0.isEmpty })
        self.location = location.flatMap { loc in
            let normalized = Normalize.token(loc)
            return normalized.isEmpty ? nil : normalized
        }
        self.weeklyCapacityHours = weeklyCapacityHours
        self.categoriesOfInterest = categoriesOfInterest
        self.preferredStages = preferredStages
        self.categoryAffinity = categoryAffinity
        self.followedOwnerIds = followedOwnerIds
    }
}

/// One dream as returned by candidate generation.
///
/// Deliberately absent: any aggregate watch/skip/completion field. That is the
/// structural guarantee that one viewer's watch behavior cannot change what
/// other viewers see — there is no input through which it could flow.
public struct DreamCandidate: Sendable, Identifiable, Equatable {
    public var id: UUID
    public var ownerId: UUID
    public var title: String
    /// dream_category raw value.
    public var category: String
    /// dream_stage raw value.
    public var stage: String
    public var location: String?
    public var helpTags: [String]
    public var helpTypes: Set<HelpType>
    public var createdAt: Date
    public var offersReceived: Int
    public var supportersCount: Int
    public var impressions: Int
    public var distinctViewers: Int
    public var isFollowedOwner: Bool
    public var hasVideo: Bool
    public var sources: Set<CandidateSource>

    public init(
        id: UUID,
        ownerId: UUID,
        title: String = "",
        category: String,
        stage: String = "idea",
        location: String? = nil,
        helpTags: [String] = [],
        helpTypes: Set<HelpType> = [],
        createdAt: Date,
        offersReceived: Int = 0,
        supportersCount: Int = 0,
        impressions: Int = 0,
        distinctViewers: Int = 0,
        isFollowedOwner: Bool = false,
        hasVideo: Bool = true,
        sources: Set<CandidateSource>
    ) {
        self.id = id
        self.ownerId = ownerId
        self.title = title
        self.category = category
        self.stage = stage
        self.location = location
        self.helpTags = helpTags
        self.helpTypes = helpTypes
        self.createdAt = createdAt
        self.offersReceived = offersReceived
        self.supportersCount = supportersCount
        self.impressions = impressions
        self.distinctViewers = distinctViewers
        self.isFollowedOwner = isFollowedOwner
        self.hasVideo = hasVideo
        self.sources = sources
    }
}

/// Every score component kept visible so tests can assert on individual terms
/// and the tuning doc can point at real numbers.
public struct ScoreBreakdown: Sendable, Equatable {
    public var helpTypeOverlap: Double
    public var skillOverlap: Double
    public var categoryAffinity: Double
    public var geoProximity: Double
    public var stageMatch: Double
    public var underServedBoost: Double
    public var recency: Double

    public var total: Double {
        helpTypeOverlap + skillOverlap + categoryAffinity
            + geoProximity + stageMatch + underServedBoost + recency
    }

    public init(
        helpTypeOverlap: Double = 0,
        skillOverlap: Double = 0,
        categoryAffinity: Double = 0,
        geoProximity: Double = 0,
        stageMatch: Double = 0,
        underServedBoost: Double = 0,
        recency: Double = 0
    ) {
        self.helpTypeOverlap = helpTypeOverlap
        self.skillOverlap = skillOverlap
        self.categoryAffinity = categoryAffinity
        self.geoProximity = geoProximity
        self.stageMatch = stageMatch
        self.underServedBoost = underServedBoost
        self.recency = recency
    }
}

/// A feed item after ranking, with the explanation the UI can surface.
public struct RankedDream: Sendable, Identifiable, Equatable {
    public var candidate: DreamCandidate
    public var score: ScoreBreakdown
    /// True when the item occupies a reserved fairness slot (placed by
    /// exposure deficit, not by score).
    public var isFairnessSlot: Bool
    public var reason: String

    public var id: UUID { candidate.id }
    public var sources: Set<CandidateSource> { candidate.sources }
}

/// Shared string normalization for matching.
enum Normalize {
    static func token(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
