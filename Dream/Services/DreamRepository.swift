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

    private enum Columns {
        static let dream = "id,owner_id,title,description,category,stage,location,help_tags,views_count,is_featured,created_at"
        static let profile = "id,handle,name,location,skills,avatar_seed,avatar_url"
        static let dreamVideo = "id,dream_id,storage_path,poster_path,duration_ms,is_primary,title,caption,created_at"
        static let commentCount = "dream_id,video_id,thread_id,comments_count"
        static let likeCount = "dream_id,video_id,thread_id,likes_count"
        static let dreamStats = "dream_id,supporters_count,offers_count"
        static let journeyStep = "id,dream_id,stage,date_label,note,done,sort_order"
    }

    // MARK: - Fetch

    /// Loads the feed: ranked (recommendation) path when enabled, with a
    /// chronological fallback so Discover is never empty (new users may have
    /// no candidates yet — everything seen, or nothing compatible).
    func loadFeed() async {
        if FeatureFlags.rankedFeedEnabled {
            await loadRankedFeed()
            if !dreams.isEmpty { return }
        }
        await loadChronologicalFeed()
    }

    /// Reverse-chronological feed (the pre-ranking behavior).
    private func loadChronologicalFeed() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let dreamRows: [DreamDTO] = try await client
                .from("dreams")
                .select(Columns.dream)
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

    /// Ranked (recommendation) path: dream ids come from the precomputed
    /// per-viewer queue (FeedQueueService → DreamRanking), rows are enriched
    /// through the existing pipeline, and the queue's order is preserved —
    /// one card per dream. The clip is seen-aware: a first encounter leads
    /// with the cover (the pitch); a returning viewer gets the newest clip
    /// (what's new since). Reachable only behind `FeatureFlags.rankedFeedEnabled`.
    func loadRankedFeed() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let entries = await FeedQueueService.shared.nextPage(count: 50)
            guard !entries.isEmpty else {
                self.dreams = []
                return
            }
            let ids = entries.map(\.id)
            async let dreamRowsFetch: [DreamDTO] = client
                .from("dreams")
                .select(Columns.dream)
                .in("id", values: ids)
                .execute()
                .value
            // RLS scopes dream_seen to the viewer's own rows.
            async let seenRowsFetch: [SeenDreamRow] = client
                .from("dream_seen")
                .select("dream_id")
                .in("dream_id", values: ids)
                .execute()
                .value
            let (dreamRows, seenRows) = try await (dreamRowsFetch, seenRowsFetch)
            let seenIds = Set(seenRows.map(\.dreamId))

            let ctx = try await fetchContext(dreamRows)
            let enriched = dreamRows.map { row -> Dream in
                let videos = ctx.videosByDream[row.id] ?? []
                let video = seenIds.contains(row.id)
                    ? videos.max(by: { $0.createdAt < $1.createdAt }) // newest clip
                    : videos.first                                    // primary (cover) first
                return Self.mapToDream(
                    row: row,
                    profile: ctx.profileByOwner[row.ownerId],
                    stats: ctx.statsByDream[row.id],
                    video: video,
                    steps: ctx.stepsByDream[row.id] ?? [],
                    comments: ctx.commentsByThread[video?.id ?? row.id] ?? 0,
                likes: ctx.likesByThread[video?.id ?? row.id] ?? 0
                )
            }
            let byId = Dictionary(enriched.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            self.dreams = ids.compactMap { byId[$0] }
        } catch {
            lastError = "\(error)"
            print("[DreamRepository] loadRankedFeed failed: \(error)")
        }
    }

    /// Drops the cached feed on sign-out, so the next account never sees the
    /// previous user's cards before its own load lands.
    func reset() {
        dreams = []
        isLoading = false
        lastError = nil
    }

    /// Removes every feed card for a dream locally ("Not interested"). The
    /// durable server-side dismissal comes from the `not_relevant` engagement
    /// event; this just makes the card disappear immediately.
    func hideDream(_ id: UUID) {
        dreams.removeAll { $0.id == id }
    }

    /// Fetches the dreams owned by a single user (newest first) as view models.
    /// Used by the profile screen. Returns `[]` and logs on failure.
    func dreams(ownedBy ownerId: UUID) async -> [Dream] {
        do {
            let dreamRows: [DreamDTO] = try await client
                .from("dreams")
                .select(Columns.dream)
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
        /// Per-thread comment counts, keyed like `Dream.feedID`
        /// (video id for clip threads, dream id for videoless dreams).
        let commentsByThread: [UUID: Int]
        /// Per-thread like counts, keyed the same way.
        let likesByThread: [UUID: Int]
    }

    /// Fetches author profiles, stats, *all* videos and journey steps for a set
    /// of dream rows concurrently and groups them by id for fast lookup.
    private func fetchContext(_ dreamRows: [DreamDTO]) async throws -> DreamContext {
        let ownerIds = Array(Set(dreamRows.map(\.ownerId)))
        let dreamIds = dreamRows.map(\.id)

        async let profiles: [ProfileDTO] = client
            .from("profiles").select(Columns.profile).in("id", values: ownerIds)
            .execute().value
        async let stats: [DreamStatsDTO] = client
            .from("dream_stats").select(Columns.dreamStats).in("dream_id", values: dreamIds)
            .execute().value
        async let videos: [DreamVideoDTO] = client
            .from("dream_videos").select(Columns.dreamVideo).in("dream_id", values: dreamIds)
            .order("is_primary", ascending: false).order("created_at", ascending: false)
            .execute().value
        async let steps: [JourneyStepDTO] = client
            .from("journey_steps").select(Columns.journeyStep).in("dream_id", values: dreamIds).order("sort_order", ascending: true)
            .execute().value
        async let commentCounts: [DreamCommentCountDTO] = client
            .from("dream_comment_counts").select(Columns.commentCount).in("dream_id", values: dreamIds)
            .execute().value
        // Deliberately not part of the `try await` group below: a failure here
        // must not take the whole feed down with it. Likes are decoration on a
        // card; the card is the point. This also means the app keeps working
        // against a database where 0028_likes hasn't been applied yet.
        async let likeCounts: [DreamLikeCountDTO] = {
            do {
                return try await client
                    .from("dream_like_counts").select(Columns.likeCount).in("dream_id", values: dreamIds)
                    .execute().value
            } catch {
                print("[DreamRepository] like counts unavailable: \(error)")
                return []
            }
        }()

        let (p, s, v, j, c) = try await (profiles, stats, videos, steps, commentCounts)
        let l = await likeCounts

        return DreamContext(
            profileByOwner: Dictionary(p.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }),
            statsByDream: Dictionary(s.map { ($0.dreamId, $0) }, uniquingKeysWith: { a, _ in a }),
            videosByDream: Dictionary(grouping: v, by: \.dreamId),
            stepsByDream: Dictionary(grouping: j, by: \.dreamId),
            commentsByThread: Dictionary(c.map { ($0.threadId, $0.commentsCount) }, uniquingKeysWith: { a, _ in a }),
            likesByThread: Dictionary(l.map { ($0.threadId, $0.likesCount) }, uniquingKeysWith: { a, _ in a })
        )
    }

    /// One `Dream` per dream row, using its primary (cover) video. Used by the
    /// profile screen, which treats a dream as a single unit.
    private func enrich(_ dreamRows: [DreamDTO]) async throws -> [Dream] {
        guard !dreamRows.isEmpty else { return [] }
        let ctx = try await fetchContext(dreamRows)
        return dreamRows.map { row in
            let video = ctx.videosByDream[row.id]?.first   // primary first
            return Self.mapToDream(
                row: row,
                profile: ctx.profileByOwner[row.ownerId],
                stats: ctx.statsByDream[row.id],
                video: video,
                steps: ctx.stepsByDream[row.id] ?? [],
                comments: ctx.commentsByThread[video?.id ?? row.id] ?? 0,
                likes: ctx.likesByThread[video?.id ?? row.id] ?? 0
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
                              Self.mapToDream(row: row, profile: profile, stats: stats, video: nil, steps: steps,
                                              comments: ctx.commentsByThread[row.id] ?? 0,
                                              likes: ctx.likesByThread[row.id] ?? 0)))
            } else {
                for video in videos {
                    // Each clip carries its own comment thread.
                    cards.append((video.createdAt,
                                  Self.mapToDream(row: row, profile: profile, stats: stats, video: video, steps: steps,
                                                  comments: ctx.commentsByThread[video.id] ?? 0,
                                                  likes: ctx.likesByThread[video.id] ?? 0)))
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
                .select(Columns.dreamVideo)
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
        do {
            let rows: [DreamDTO] = try await client
                .from("dreams")
                .select(Columns.dream)
                .eq("owner_id", value: userId)
                .order("is_featured", ascending: false)
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else { return nil }
            return Self.mapToDream(row: row, profile: nil, stats: nil, video: nil, steps: [])
        } catch {
            lastError = "\(error)"
            print("[DreamRepository] myDream failed: \(error)")
            return nil
        }
    }

    // MARK: - Featured ("main") dream

    /// Marks `dreamId` as the current user's single featured dream, clearing any
    /// previously-featured dream first (a partial unique index allows only one).
    /// Not atomic — a partial-unique index forbids two featured dreams at once,
    /// so the old one must be cleared before the new one is set. If the second
    /// update fails the user is left with no featured dream rather than the
    /// wrong one, and the throw surfaces that; re-picking fixes it. Skips the
    /// work entirely when the target is already featured.
    func setFeatured(dreamId: UUID, ownerId: UUID) async throws {
        let alreadyFeatured: [DreamIdRow] = try await client
            .from("dreams")
            .select("id")
            .eq("owner_id", value: ownerId)
            .eq("is_featured", value: true)
            .execute()
            .value
        if alreadyFeatured.count == 1, alreadyFeatured[0].id == dreamId { return }

        if !alreadyFeatured.isEmpty {
            try await client
                .from("dreams")
                .update(["is_featured": false])
                .eq("owner_id", value: ownerId)
                .eq("is_featured", value: true)
                .execute()
        }

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
        guard let userId = try? await client.auth.session.user.id else {
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
        steps: [JourneyStepDTO],
        comments: Int = 0,
        likes: Int = 0
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
            avatarURL: profile?.avatarURLValue,
            location: row.location ?? profile?.location ?? "",
            desc: row.description,
            journey: journey,
            supporters: stats?.supportersCount ?? 0,
            offers: stats?.offersCount ?? 0,
            viewsLabel: formatCount(row.viewsCount),
            isFeatured: row.isFeatured,
            posterURL: posterURL,
            videoStoragePath: video?.storagePath,
            videoId: video?.id,
            videoTitle: video?.title,
            videoCaption: video?.caption,
            videoDurationMs: video?.durationMs,
            comments: comments,
            likes: likes
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
