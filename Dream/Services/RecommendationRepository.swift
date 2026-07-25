import Combine
import DreamRanking
import Foundation
import Supabase

/// Thin wrapper over the recommendation RPCs. All scoring happens in the
/// DreamRanking package — this type only moves data.
@MainActor
final class RecommendationRepository: ObservableObject {
    static let shared = RecommendationRepository()

    private let client = SupabaseService.shared.client
    private init() {}

    /// The viewer as the ranker sees them: capabilities, interests, follows,
    /// and learned category affinity (from their own engagement only).
    func fetchViewerProfile() async throws -> ViewerProfile {
        let rows: [ViewerRankingProfileDTO] = try await client
            .rpc("get_viewer_ranking_profile")
            .execute()
            .value
        guard let row = rows.first else {
            throw NSError(domain: "RecommendationRepository", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "No profile for current user"])
        }
        return row.viewerProfile
    }

    /// Raw multi-source candidate pool (~300) for on-device ranking.
    func fetchCandidates(config: RankingConfig = .default) async throws -> [DreamCandidate] {
        struct Params: Encodable {
            let p_limit: Int
            let p_seen_ttl_days: Int
            let p_underexposed_viewer_floor: Int
        }
        let rows: [FeedCandidateDTO] = try await client
            .rpc("get_feed_candidates", params: Params(
                p_limit: config.candidateLimit,
                p_seen_ttl_days: config.seenTTLDays,
                p_underexposed_viewer_floor: config.exposureViewerFloor
            ))
            .execute()
            .value
        return rows.map(\.candidate)
    }

    /// The current user's saved supporter capability profile, if any.
    /// Backs the "How you can help" section of EditProfileScreen.
    func fetchSupporterProfile() async -> SupporterProfilePayload? {
        guard let userId = try? await client.auth.session.user.id else { return nil }
        do {
            let rows: [SupporterProfilePayload] = try await client
                .from("supporter_profiles")
                .select("user_id,help_types,weekly_capacity_hours,categories_of_interest,preferred_stages")
                .eq("user_id", value: userId)
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch {
            print("[RecommendationRepository] fetchSupporterProfile failed: \(error)")
            return nil
        }
    }

    /// Saves the current user's supporter capability profile — what the
    /// matching algorithm routes dreams against.
    func upsertSupporterProfile(
        helpTypes: [HelpType],
        weeklyCapacityHours: Int,
        categoriesOfInterest: [DreamCategory],
        preferredStages: [DreamStage]
    ) async throws {
        guard let userId = try? await client.auth.session.user.id else {
            throw NSError(domain: "RecommendationRepository", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }
        let payload = SupporterProfilePayload(
            userId: userId,
            helpTypes: helpTypes.map(\.rawValue),
            weeklyCapacityHours: weeklyCapacityHours,
            categoriesOfInterest: categoriesOfInterest.map(\.dbValue),
            preferredStages: preferredStages.map(\.dbValue)
        )
        try await client
            .from("supporter_profiles")
            .upsert(payload)
            .execute()
    }
}
