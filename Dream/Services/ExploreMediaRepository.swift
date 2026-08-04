import Combine
import DreamRanking
import Foundation
import Supabase

enum ExploreMediaKind {
    case video
    case photo
}

struct ExploreMediaItem: Identifiable {
    let id: UUID
    let kind: ExploreMediaKind
    let createdAt: Date
    let dreamId: UUID
    let ownerId: UUID
    let authorName: String
    let handle: String
    let avatarSeed: Int
    let avatarURL: URL?
    let location: String
    let category: DreamCategory
    let dreamTitle: String
    let title: String
    let caption: String?
    let imageURL: URL?
    let videoStoragePath: String?
    let isPrimaryVideo: Bool
    let dream: Dream
    let videoDream: Dream?

    var displayTitle: String {
        title.isEmpty ? dreamTitle : title
    }
}

@MainActor
final class ExploreMediaRepository: ObservableObject {
    static let shared = ExploreMediaRepository()

    @Published private(set) var items: [ExploreMediaItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    private let client = SupabaseService.shared.client
    private init() {}

    private enum Columns {
        static let dream = "id,owner_id,title,description,category,stage,location,help_tags,views_count,is_featured,created_at"
        static let profile = "id,handle,name,location,skills,avatar_seed,avatar_url"
        static let video = "id,dream_id,storage_path,poster_path,is_primary,title,caption,created_at"
        static let photo = "id,dream_id,image_path,title,caption,width,height,created_at"
        static let stats = "dream_id,supporters_count,offers_count"
        static let step = "id,dream_id,stage,date_label,note,done,sort_order"
    }

    /// Loads the Explore grid through the ranker with the browsing preset
    /// (`RankingConfig.explore`: fresh + interests first, fairness at full
    /// strength, no seen-TTL — only "Not interested" dreams stay hidden).
    /// Falls back to the plain recency grid on any ranking failure, and
    /// degrades to recency ordering by construction when the ranked list is
    /// empty, so Explore is never blank.
    func loadFeed(limit: Int = 150) async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await fetchRankedMedia(limit: limit)
            lastError = nil
        } catch {
            print("[ExploreMediaRepository] ranked load failed, falling back to recency: \(error)")
            do {
                items = try await fetchMedia(limit: limit, ownerId: nil, includePrimaryVideos: true)
                lastError = nil
            } catch {
                lastError = "\(error)"
                print("[ExploreMediaRepository] loadFeed failed: \(error)")
            }
        }
    }

    /// Ranked grid: dreams ordered by the explore-config ranker, each dream's
    /// media newest-first, unranked leftovers (own dreams, anything outside
    /// the candidate pool) trailing by recency. The media pool is the recent
    /// window PLUS media for the top-ranked dreams, so under-exposed dreams
    /// keep grid presence even when their clips are old.
    private func fetchRankedMedia(limit: Int) async throws -> [ExploreMediaItem] {
        let config = RankingConfig.explore
        let recommendations = RecommendationRepository.shared

        async let viewerFetch = recommendations.fetchViewerProfile()
        async let candidatesFetch = recommendations.fetchCandidates(config: config)
        // RLS scopes this to the viewer's own rows; the limit just keeps a
        // heavy dismisser from pulling an unbounded list on every Explore open.
        async let dismissedFetch: [SeenDreamRow] = client
            .from("dream_seen")
            .select("dream_id")
            .eq("dismissed", value: true)
            .limit(500)
            .execute()
            .value
        let (viewer, candidates, dismissedRows) = try await (viewerFetch, candidatesFetch, dismissedFetch)

        let ranked = DreamRanker.rank(
            candidates: candidates, viewer: viewer, config: config, now: Date())
        var rankIndexByDream: [UUID: Int] = [:]
        for (index, item) in ranked.enumerated() { rankIndexByDream[item.id] = index }
        let dismissed = Set(dismissedRows.map(\.dreamId))

        let recentVideos = await fetchVideos(limit: 120, dreamIds: nil, includePrimaryVideos: true)
        let recentPhotos = await fetchPhotos(limit: 120, dreamIds: nil)
        var rankedVideos: [DreamVideoDTO] = []
        var rankedPhotos: [DreamPhotoUpdateDTO] = []
        let topRankedIds = Array(ranked.prefix(60).map(\.id))
        if !topRankedIds.isEmpty {
            rankedVideos = await fetchVideos(limit: 120, dreamIds: topRankedIds, includePrimaryVideos: true)
            rankedPhotos = await fetchPhotos(limit: 120, dreamIds: topRankedIds)
        }

        var videoById: [UUID: DreamVideoDTO] = [:]
        for row in recentVideos + rankedVideos { videoById[row.id] = row }
        var photoById: [UUID: DreamPhotoUpdateDTO] = [:]
        for row in recentPhotos + rankedPhotos { photoById[row.id] = row }

        // Order, filter and truncate on the raw rows *before* enrichment.
        // The final ordering only depends on (dream rank, createdAt), both of
        // which are known here, so the result is identical to sorting after —
        // but the four overlapping fetches above yield ~480 rows for a 150-item
        // grid, and enriching all of them meant pulling dreams, every clip,
        // stats, journey steps and profiles for ~3x the dreams actually shown.
        func precedes(_ leftDream: UUID, _ leftDate: Date, _ rightDream: UUID, _ rightDate: Date) -> Bool {
            let leftRank = rankIndexByDream[leftDream] ?? Int.max
            let rightRank = rankIndexByDream[rightDream] ?? Int.max
            if leftRank != rightRank { return leftRank < rightRank }
            return leftDate > rightDate
        }

        enum Row {
            case video(DreamVideoDTO)
            case photo(DreamPhotoUpdateDTO)

            var dreamId: UUID {
                switch self {
                case .video(let v): return v.dreamId
                case .photo(let p): return p.dreamId
                }
            }
            var createdAt: Date {
                switch self {
                case .video(let v): return v.createdAt
                case .photo(let p): return p.createdAt
                }
            }
        }

        // Small margin over `limit`: buildItems drops any row whose dream it
        // can't resolve (deleted dream with orphaned media), and those used to
        // be discarded before the truncation. The spare rows keep a full grid.
        let ordered = (videoById.values.map(Row.video) + photoById.values.map(Row.photo))
            .filter { !dismissed.contains($0.dreamId) }
            .sorted { precedes($0.dreamId, $0.createdAt, $1.dreamId, $1.createdAt) }
            .prefix(limit + 30)

        var keptVideos: [DreamVideoDTO] = []
        var keptPhotos: [DreamPhotoUpdateDTO] = []
        for row in ordered {
            switch row {
            case .video(let v): keptVideos.append(v)
            case .photo(let p): keptPhotos.append(p)
            }
        }

        let built = try await buildItems(videos: keptVideos, photos: keptPhotos, limit: limit + 30)
        // buildItems orders by recency alone, so re-apply the ranked order.
        return Array(
            built
                .sorted { precedes($0.dreamId, $0.createdAt, $1.dreamId, $1.createdAt) }
                .prefix(limit)
        )
    }

    /// Drops every grid item belonging to a user the viewer just blocked, so
    /// the block shows up without waiting for a reload.
    func removeContent(ownedBy ownerId: UUID) {
        items.removeAll { $0.ownerId == ownerId }
    }

    /// Drops the cached grid on sign-out.
    func reset() {
        items = []
        isLoading = false
        lastError = nil
    }

    func media(ownedBy ownerId: UUID, includePrimaryVideos: Bool = false, limit: Int = 120) async -> [ExploreMediaItem] {
        do {
            return try await fetchMedia(limit: limit, ownerId: ownerId, includePrimaryVideos: includePrimaryVideos)
        } catch {
            print("[ExploreMediaRepository] media(ownedBy:) failed: \(error)")
            return []
        }
    }

    private func fetchMedia(limit: Int, ownerId: UUID?, includePrimaryVideos: Bool) async throws -> [ExploreMediaItem] {
        let dreamIdsForOwner: [UUID]?
        if let ownerId {
            let dreamRows: [DreamDTO] = try await client
                .from("dreams")
                .select(Columns.dream)
                .eq("owner_id", value: ownerId)
                .order("created_at", ascending: false)
                .limit(80)
                .execute()
                .value
            dreamIdsForOwner = dreamRows.map(\.id)
            if dreamRows.isEmpty { return [] }
        } else {
            dreamIdsForOwner = nil
        }

        async let videos = fetchVideos(limit: limit, dreamIds: dreamIdsForOwner, includePrimaryVideos: includePrimaryVideos)
        async let photos = fetchPhotos(limit: limit, dreamIds: dreamIdsForOwner)
        let (videoRows, photoRows) = await (videos, photos)
        return try await buildItems(videos: videoRows, photos: photoRows, limit: limit)
    }

    private func fetchVideos(limit: Int, dreamIds: [UUID]?, includePrimaryVideos: Bool) async -> [DreamVideoDTO] {
        do {
            if let dreamIds, !includePrimaryVideos {
                return try await client
                    .from("dream_videos")
                    .select(Columns.video)
                    .in("dream_id", values: dreamIds)
                    .eq("is_primary", value: false)
                    .order("created_at", ascending: false)
                    .limit(limit)
                    .execute()
                    .value
            }
            if !includePrimaryVideos {
                return try await client
                    .from("dream_videos")
                    .select(Columns.video)
                    .eq("is_primary", value: false)
                    .order("created_at", ascending: false)
                    .limit(limit)
                    .execute()
                    .value
            }
            if let dreamIds {
                return try await client
                    .from("dream_videos")
                    .select(Columns.video)
                    .in("dream_id", values: dreamIds)
                    .order("created_at", ascending: false)
                    .limit(limit)
                    .execute()
                    .value
            }
            return try await client
                .from("dream_videos")
                .select(Columns.video)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
        } catch {
            print("[ExploreMediaRepository] fetchVideos failed: \(error)")
            return []
        }
    }

    private func fetchPhotos(limit: Int, dreamIds: [UUID]?) async -> [DreamPhotoUpdateDTO] {
        do {
            if let dreamIds {
                return try await client
                    .from("dream_photo_updates")
                    .select(Columns.photo)
                    .in("dream_id", values: dreamIds)
                    .order("created_at", ascending: false)
                    .limit(limit)
                    .execute()
                    .value
            }
            return try await client
                .from("dream_photo_updates")
                .select(Columns.photo)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
        } catch {
            print("[ExploreMediaRepository] fetchPhotos failed: \(error)")
            return []
        }
    }

    private func buildItems(videos: [DreamVideoDTO], photos: [DreamPhotoUpdateDTO], limit: Int) async throws -> [ExploreMediaItem] {
        let dreamIds = Array(Set(videos.map(\.dreamId) + photos.map(\.dreamId)))
        guard !dreamIds.isEmpty else { return [] }

        async let dreamRows: [DreamDTO] = client
            .from("dreams")
            .select(Columns.dream)
            .in("id", values: dreamIds)
            .execute()
            .value
        async let allVideos: [DreamVideoDTO] = client
            .from("dream_videos")
            .select(Columns.video)
            .in("dream_id", values: dreamIds)
            .order("is_primary", ascending: false)
            .order("created_at", ascending: false)
            .execute()
            .value
        async let stats: [DreamStatsDTO] = client
            .from("dream_stats")
            .select(Columns.stats)
            .in("dream_id", values: dreamIds)
            .execute()
            .value
        async let steps: [JourneyStepDTO] = client
            .from("journey_steps")
            .select(Columns.step)
            .in("dream_id", values: dreamIds)
            .order("sort_order", ascending: true)
            .execute()
            .value

        let (dreams, dreamVideos, statRows, stepRows) = try await (dreamRows, allVideos, stats, steps)
        let ownerIds = Array(Set(dreams.map(\.ownerId)))
        let profiles: [ProfileDTO] = ownerIds.isEmpty ? [] : try await client
            .from("profiles")
            .select(Columns.profile)
            .in("id", values: ownerIds)
            .execute()
            .value

        let dreamById = Dictionary(dreams.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let profileByOwner = Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let statsByDream = Dictionary(statRows.map { ($0.dreamId, $0) }, uniquingKeysWith: { a, _ in a })
        let stepsByDream = Dictionary(grouping: stepRows, by: \.dreamId)
        let videosByDream = Dictionary(grouping: dreamVideos, by: \.dreamId)

        var result: [ExploreMediaItem] = []

        for row in videos {
            guard let dream = dreamById[row.dreamId] else { continue }
            let profile = profileByOwner[dream.ownerId]
            let parentVideo = primaryVideo(from: videosByDream[row.dreamId])
            let parentDream = mapDream(row: dream, profile: profile, stats: statsByDream[dream.id], video: parentVideo, steps: stepsByDream[dream.id] ?? [])
            let mediaDream = mapDream(row: dream, profile: profile, stats: statsByDream[dream.id], video: row, steps: stepsByDream[dream.id] ?? [])
            let posterURL = row.posterPath.flatMap { path in
                try? client.storage.from("dream-posters").getPublicURL(path: path)
            }
            result.append(
                item(
                    id: row.id,
                    kind: .video,
                    createdAt: row.createdAt,
                    dream: dream,
                    profile: profile,
                    title: row.title ?? dream.title,
                    caption: cleaned(row.caption) ?? (row.isPrimary ? cleaned(dream.description) : nil),
                    imageURL: posterURL,
                    videoStoragePath: row.storagePath,
                    isPrimaryVideo: row.isPrimary,
                    parentDream: parentDream,
                    videoDream: mediaDream
                )
            )
        }

        for row in photos {
            guard let dream = dreamById[row.dreamId] else { continue }
            let profile = profileByOwner[dream.ownerId]
            let parentVideo = primaryVideo(from: videosByDream[row.dreamId])
            let parentDream = mapDream(row: dream, profile: profile, stats: statsByDream[dream.id], video: parentVideo, steps: stepsByDream[dream.id] ?? [])
            let imageURL = try? client.storage.from("dream-images").getPublicURL(path: row.imagePath)
            result.append(
                item(
                    id: row.id,
                    kind: .photo,
                    createdAt: row.createdAt,
                    dream: dream,
                    profile: profile,
                    title: row.title,
                    caption: cleaned(row.caption),
                    imageURL: imageURL,
                    videoStoragePath: nil,
                    isPrimaryVideo: false,
                    parentDream: parentDream,
                    videoDream: nil
                )
            )
        }

        return result
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    private func item(
        id: UUID,
        kind: ExploreMediaKind,
        createdAt: Date,
        dream: DreamDTO,
        profile: ProfileDTO?,
        title: String,
        caption: String?,
        imageURL: URL?,
        videoStoragePath: String?,
        isPrimaryVideo: Bool,
        parentDream: Dream,
        videoDream: Dream?
    ) -> ExploreMediaItem {
        ExploreMediaItem(
            id: id,
            kind: kind,
            createdAt: createdAt,
            dreamId: dream.id,
            ownerId: dream.ownerId,
            authorName: profile?.name ?? "Anonymous",
            handle: profile?.handle ?? "anon",
            avatarSeed: profile?.avatarSeed ?? 0,
            avatarURL: profile?.avatarURLValue,
            location: dream.location ?? profile?.location ?? "",
            category: DreamCategory.from(dbValue: dream.category),
            dreamTitle: dream.title,
            title: title,
            caption: caption,
            imageURL: imageURL,
            videoStoragePath: videoStoragePath,
            isPrimaryVideo: isPrimaryVideo,
            dream: parentDream,
            videoDream: videoDream
        )
    }

    private func primaryVideo(from videos: [DreamVideoDTO]?) -> DreamVideoDTO? {
        guard let videos else { return nil }
        return videos.first(where: \.isPrimary) ?? videos.first
    }

    private func mapDream(
        row: DreamDTO,
        profile: ProfileDTO?,
        stats: DreamStatsDTO?,
        video: DreamVideoDTO?,
        steps: [JourneyStepDTO]
    ) -> Dream {
        let journey = steps.map {
            JourneyStep(id: $0.id, stage: $0.stage, date: $0.dateLabel, done: $0.done, note: $0.note)
        }
        let posterURL = video?.posterPath.flatMap { path in
            try? client.storage.from("dream-posters").getPublicURL(path: path)
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
            videoCaption: video?.caption
        )
    }

    private func cleaned(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1000 {
            let k = Double(n) / 1000.0
            return String(format: "%.1fk", k)
        }
        return "\(n)"
    }
}
