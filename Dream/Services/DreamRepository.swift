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

            self.dreams = try await enrichFeed(dreamRows)
        } catch {
            lastError = "\(error)"
            print("[DreamRepository] loadFeed failed: \(error)")
        }
    }

    /// Fetches the dreams owned by a single user (newest first) as view models.
    /// Used by the profile screen. Returns `[]` and logs on failure.
    func dreams(ownedBy ownerId: UUID) async -> [Dream] {
        do {
            let dreamRows: [DreamDTO] = try await client
                .from("dreams")
                .select()
                .eq("owner_id", value: ownerId)
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value
            return try await enrich(dreamRows)
        } catch {
            print("[DreamRepository] dreams(ownedBy:) failed: \(error)")
            return []
        }
    }

    /// The author/stats/steps/videos needed to turn dream rows into view models.
    private struct DreamContext {
        let profileByOwner: [UUID: ProfileDTO]
        let statsByDream: [UUID: DreamStatsDTO]
        let videosByDream: [UUID: [DreamVideoDTO]]   // primary first, then newest
        let stepsByDream: [UUID: [JourneyStepDTO]]
    }

    /// Fetches author profiles, stats, *all* videos and journey steps for a set
    /// of dream rows concurrently and groups them by id for fast lookup.
    private func fetchContext(_ dreamRows: [DreamDTO]) async throws -> DreamContext {
        let ownerIds = Array(Set(dreamRows.map(\.ownerId)))
        let dreamIds = dreamRows.map(\.id)

        async let profiles: [ProfileDTO] = client
            .from("profiles").select().in("id", values: ownerIds)
            .execute().value
        async let stats: [DreamStatsDTO] = client
            .from("dream_stats").select().in("dream_id", values: dreamIds)
            .execute().value
        async let videos: [DreamVideoDTO] = client
            .from("dream_videos").select().in("dream_id", values: dreamIds)
            .order("is_primary", ascending: false).order("created_at", ascending: false)
            .execute().value
        async let steps: [JourneyStepDTO] = client
            .from("journey_steps").select().in("dream_id", values: dreamIds).order("sort_order", ascending: true)
            .execute().value

        let (p, s, v, j) = try await (profiles, stats, videos, steps)

        return DreamContext(
            profileByOwner: Dictionary(p.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }),
            statsByDream: Dictionary(s.map { ($0.dreamId, $0) }, uniquingKeysWith: { a, _ in a }),
            videosByDream: Dictionary(grouping: v, by: \.dreamId),
            stepsByDream: Dictionary(grouping: j, by: \.dreamId)
        )
    }

    /// One `Dream` per dream row, using its primary (cover) video. Used by the
    /// profile screen, which treats a dream as a single unit.
    private func enrich(_ dreamRows: [DreamDTO]) async throws -> [Dream] {
        guard !dreamRows.isEmpty else { return [] }
        let ctx = try await fetchContext(dreamRows)
        return dreamRows.map { row in
            Self.mapToDream(
                row: row,
                profile: ctx.profileByOwner[row.ownerId],
                stats: ctx.statsByDream[row.id],
                video: ctx.videosByDream[row.id]?.first,   // primary first
                steps: ctx.stepsByDream[row.id] ?? []
            )
        }
    }

    /// One feed card *per video*: a dream's main clip and every update clip each
    /// surface as their own card, interleaved across all dreams by recency so
    /// fresh updates show up in Discover. Dreams without any video still produce
    /// one (gradient) card. Used by `loadFeed`.
    private func enrichFeed(_ dreamRows: [DreamDTO]) async throws -> [Dream] {
        guard !dreamRows.isEmpty else { return [] }
        let ctx = try await fetchContext(dreamRows)

        var cards: [(date: Date, dream: Dream)] = []
        for row in dreamRows {
            let profile = ctx.profileByOwner[row.ownerId]
            let stats = ctx.statsByDream[row.id]
            let steps = ctx.stepsByDream[row.id] ?? []
            let videos = ctx.videosByDream[row.id] ?? []

            if videos.isEmpty {
                cards.append((row.createdAt,
                              Self.mapToDream(row: row, profile: profile, stats: stats, video: nil, steps: steps)))
            } else {
                for video in videos {
                    cards.append((video.createdAt,
                                  Self.mapToDream(row: row, profile: profile, stats: stats, video: video, steps: steps)))
                }
            }
        }
        return cards.sorted { $0.date > $1.date }.map(\.dream)
    }

    /// Fetches every video for a dream (primary first, then newest), resolving
    /// each poster's public URL. Used by the profile to show the main dream's clips.
    func videos(forDream dreamId: UUID) async -> [DreamMedia] {
        do {
            let rows: [DreamVideoDTO] = try await client
                .from("dream_videos")
                .select()
                .eq("dream_id", value: dreamId)
                .order("is_primary", ascending: false)
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value
            return rows.map { v in
                let posterURL = v.posterPath.flatMap { path in
                    try? client.storage.from("dream-posters").getPublicURL(path: path)
                }
                return DreamMedia(id: v.id, storagePath: v.storagePath, posterURL: posterURL, isPrimary: v.isPrimary)
            }
        } catch {
            print("[DreamRepository] videos(forDream:) failed: \(error)")
            return []
        }
    }

    /// The current user's dream that updates attach to: their featured dream if
    /// they've pinned one, else their most recent. `nil` if they have none yet.
    func myDream() async -> Dream? {
        guard let userId = try? await client.auth.session.user.id else { return nil }
        let owned = await dreams(ownedBy: userId)
        return owned.first(where: { $0.isFeatured }) ?? owned.first
    }

    // MARK: - Featured ("main") dream

    /// Marks `dreamId` as the current user's single featured dream, clearing any
    /// previously-featured dream first (a partial unique index allows only one).
    func setFeatured(dreamId: UUID, ownerId: UUID) async throws {
        try await client
            .from("dreams")
            .update(["is_featured": false])
            .eq("owner_id", value: ownerId)
            .eq("is_featured", value: true)
            .execute()

        try await client
            .from("dreams")
            .update(["is_featured": true])
            .eq("id", value: dreamId)
            .execute()
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
            ownerId: row.ownerId,
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
            isFeatured: row.isFeatured,
            videoURL: nil, // private bucket — fetch signed URL on demand
            posterURL: posterURL,
            videoStoragePath: video?.storagePath,
            videoId: video?.id,
            videoTitle: video?.title
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
