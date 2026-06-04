import Combine
import Foundation
import Supabase

/// Reads/writes dreams from Supabase and maps DB rows into the `Dream` view model.
@MainActor
final class DreamRepository: ObservableObject {
    static let shared = DreamRepository()

    @Published private(set) var dreams: [Dream] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    private let client = SupabaseService.shared.client
    private init() {}

    // MARK: - Fetch

    /// Loads dreams + author profiles + stats + primary video and produces view models.
    func loadFeed() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let dreamRows: [DreamDTO] = try await client
                .from("dreams")
                .select()
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value

            guard !dreamRows.isEmpty else {
                self.dreams = []
                return
            }

            let ownerIds = Array(Set(dreamRows.map(\.ownerId)))
            let dreamIds = dreamRows.map(\.id)

            async let profiles: [ProfileDTO] = client
                .from("profiles").select().in("id", values: ownerIds)
                .execute().value
            async let stats: [DreamStatsDTO] = client
                .from("dream_stats").select().in("dream_id", values: dreamIds)
                .execute().value
            async let videos: [DreamVideoDTO] = client
                .from("dream_videos").select().in("dream_id", values: dreamIds).eq("is_primary", value: true)
                .execute().value
            async let steps: [JourneyStepDTO] = client
                .from("journey_steps").select().in("dream_id", values: dreamIds).order("sort_order", ascending: true)
                .execute().value

            let (p, s, v, j) = try await (profiles, stats, videos, steps)

            let profileById = Dictionary(uniqueKeysWithValues: p.map { ($0.id, $0) })
            let statsById = Dictionary(uniqueKeysWithValues: s.map { ($0.dreamId, $0) })
            let videoByDream = Dictionary(uniqueKeysWithValues: v.map { ($0.dreamId, $0) })
            let stepsByDream = Dictionary(grouping: j, by: \.dreamId)

            self.dreams = dreamRows.map { row in
                Self.mapToDream(
                    row: row,
                    profile: profileById[row.ownerId],
                    stats: statsById[row.id],
                    video: videoByDream[row.id],
                    steps: stepsByDream[row.id] ?? []
                )
            }
        } catch {
            lastError = "\(error)"
            print("[DreamRepository] loadFeed failed: \(error)")
        }
    }

    // MARK: - Create

    /// Inserts a dream row owned by the current authed user and returns its UUID.
    func createDream(
        title: String,
        description: String,
        category: DreamCategory,
        stage: DreamStage,
        location: String?,
        helpTags: [String]
    ) async throws -> UUID {
        guard let userId = try await client.auth.session.user.id as UUID? else {
            throw NSError(domain: "DreamRepository", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }

        let payload = NewDreamPayload(
            owner_id: userId,
            title: title,
            description: description,
            category: category.dbValue,
            stage: stage.dbValue,
            location: location,
            help_tags: helpTags
        )

        let inserted: DreamDTO = try await client
            .from("dreams")
            .insert(payload, returning: .representation)
            .select()
            .single()
            .execute()
            .value

        return inserted.id
    }

    // MARK: - Mapping

    private static func mapToDream(
        row: DreamDTO,
        profile: ProfileDTO?,
        stats: DreamStatsDTO?,
        video: DreamVideoDTO?,
        steps: [JourneyStepDTO]
    ) -> Dream {
        let journey = steps.map { step in
            JourneyStep(
                id: step.id,
                stage: step.stage,
                date: step.dateLabel,
                done: step.done,
                note: step.note
            )
        }

        let posterURL = video?.posterPath.flatMap { path in
            try? SupabaseService.shared.client.storage
                .from("dream-posters")
                .getPublicURL(path: path)
        }

        return Dream(
            id: row.id,
            name: profile?.name ?? "Anonymous",
            handle: profile?.handle ?? "anon",
            title: row.title,
            category: DreamCategory.from(dbValue: row.category),
            stage: DreamStage.from(dbValue: row.stage),
            help: row.helpTags,
            avatarSeed: profile?.avatarSeed ?? 0,
            location: row.location ?? profile?.location ?? "",
            distance: "",
            desc: row.description,
            journey: journey,
            supporters: stats?.supportersCount ?? 0,
            offers: stats?.offersCount ?? 0,
            viewsLabel: formatCount(row.viewsCount),
            videoURL: nil, // private bucket — fetch signed URL on demand
            posterURL: posterURL,
            videoStoragePath: video?.storagePath
        )
    }

    private static func formatCount(_ n: Int) -> String {
        if n >= 1000 {
            let k = Double(n) / 1000.0
            return String(format: "%.1fk", k)
        }
        return "\(n)"
    }
}
