import Combine
import Foundation
import Supabase

// MARK: - DTOs

/// One row per liked card. `threadId` is the generated `coalesce(video_id,
/// dream_id)` — the same key as `Dream.feedID`.
struct DreamLikeDTO: Codable, Hashable {
    let dreamId: UUID
    let videoId: UUID?
    let threadId: UUID

    enum CodingKeys: String, CodingKey {
        case dreamId = "dream_id"
        case videoId = "video_id"
        case threadId = "thread_id"
    }
}

struct DreamLikeCountDTO: Codable, Hashable {
    let dreamId: UUID
    let videoId: UUID?
    let threadId: UUID
    let likesCount: Int

    enum CodingKeys: String, CodingKey {
        case dreamId = "dream_id"
        case videoId = "video_id"
        case threadId = "thread_id"
        case likesCount = "likes_count"
    }
}

// MARK: - Store

/// The viewer's own likes, plus the counts shown on each card.
///
/// Toggling is optimistic: the heart and the count move immediately and roll
/// back if the write fails. A like is a cheap, high-frequency action — waiting
/// on a round trip before the heart fills makes the whole feed feel slow.
///
/// Keyed by `Dream.feedID`, so each video card is liked separately, matching
/// how comments are threaded.
@MainActor
final class LikesStore: ObservableObject {
    static let shared = LikesStore()

    /// Thread ids (`Dream.feedID`) the viewer has liked.
    @Published private(set) var likedIDs: Set<UUID> = []
    /// Live per-card counts, overriding whatever the feed was enriched with.
    @Published private(set) var counts: [UUID: Int] = [:]

    private let repository = LikeRepository()
    private var inFlight: Set<UUID> = []

    private init() {}

    func isLiked(_ feedID: UUID) -> Bool { likedIDs.contains(feedID) }

    /// Count for a card, preferring a live value over the enriched one.
    func count(for feedID: UUID, fallback: Int) -> Int {
        counts[feedID] ?? fallback
    }

    /// Loads the viewer's likes and the counts for a set of dreams. Safe to call
    /// on every feed load; it replaces rather than accumulates.
    func load(forDreams dreamIds: [UUID], viewer: UUID?) async {
        guard !dreamIds.isEmpty else { return }
        async let fetchedCounts = repository.counts(forDreams: dreamIds)
        async let mine: Set<UUID> = {
            guard let viewer else { return [] }
            return await repository.likedThreads(forDreams: dreamIds, viewer: viewer)
        }()

        let (c, m) = await (fetchedCounts, mine)
        counts.merge(c) { _, new in new }
        likedIDs.formUnion(m)
    }

    /// Optimistically flips the like and reconciles with the server.
    func toggle(dreamId: UUID, videoId: UUID?, viewer: UUID?, currentCount: Int) {
        guard let viewer else { return }
        let feedID = videoId ?? dreamId
        // Ignore a second tap while the first is still settling, so a double tap
        // can't leave the local state and the server disagreeing.
        guard !inFlight.contains(feedID) else { return }
        inFlight.insert(feedID)

        let wasLiked = likedIDs.contains(feedID)
        let base = counts[feedID] ?? currentCount

        if wasLiked {
            likedIDs.remove(feedID)
            counts[feedID] = max(0, base - 1)
        } else {
            likedIDs.insert(feedID)
            counts[feedID] = base + 1
            EngagementLogger.shared.log(.like, dreamId: dreamId)
        }

        Task {
            let ok = wasLiked
                ? await repository.unlike(dreamId: dreamId, videoId: videoId, viewer: viewer)
                : await repository.like(dreamId: dreamId, videoId: videoId, viewer: viewer)

            if !ok {
                // Roll back to exactly what we had, not to a recomputed guess.
                if wasLiked {
                    likedIDs.insert(feedID)
                } else {
                    likedIDs.remove(feedID)
                }
                counts[feedID] = base
            }
            inFlight.remove(feedID)
        }
    }
}

// MARK: - Repository

@MainActor
final class LikeRepository {
    private let client = SupabaseService.shared.client

    private enum Columns {
        static let like = "dream_id,video_id,thread_id"
        static let count = "dream_id,video_id,thread_id,likes_count"
    }

    /// Per-card like counts, keyed by thread id.
    func counts(forDreams dreamIds: [UUID]) async -> [UUID: Int] {
        guard !dreamIds.isEmpty else { return [:] }
        do {
            let rows: [DreamLikeCountDTO] = try await client
                .from("dream_like_counts")
                .select(Columns.count)
                .in("dream_id", values: dreamIds)
                .execute()
                .value
            return Dictionary(rows.map { ($0.threadId, $0.likesCount) }, uniquingKeysWith: { a, _ in a })
        } catch {
            print("[LikeRepository] counts(forDreams:) failed: \(error)")
            return [:]
        }
    }

    /// Which of these dreams' cards the viewer has already liked.
    func likedThreads(forDreams dreamIds: [UUID], viewer: UUID) async -> Set<UUID> {
        guard !dreamIds.isEmpty else { return [] }
        do {
            let rows: [DreamLikeDTO] = try await client
                .from("dream_likes")
                .select(Columns.like)
                .eq("user_id", value: viewer)
                .in("dream_id", values: dreamIds)
                .execute()
                .value
            return Set(rows.map(\.threadId))
        } catch {
            print("[LikeRepository] likedThreads(forDreams:) failed: \(error)")
            return []
        }
    }

    func like(dreamId: UUID, videoId: UUID?, viewer: UUID) async -> Bool {
        struct Payload: Encodable {
            let dreamId: UUID
            let videoId: UUID?
            let userId: UUID

            enum CodingKeys: String, CodingKey {
                case dreamId = "dream_id"
                case videoId = "video_id"
                case userId = "user_id"
            }
        }
        do {
            try await client
                .from("dream_likes")
                .insert(Payload(dreamId: dreamId, videoId: videoId, userId: viewer))
                .execute()
            return true
        } catch {
            // A duplicate means the viewer already liked this card — the local
            // state was simply behind, so treat it as success rather than
            // rolling the heart back under them.
            if "\(error)".contains("dream_likes_one_per_viewer_idx") { return true }
            print("[LikeRepository] like failed: \(error)")
            return false
        }
    }

    func unlike(dreamId: UUID, videoId: UUID?, viewer: UUID) async -> Bool {
        do {
            let query = client
                .from("dream_likes")
                .delete()
                .eq("user_id", value: viewer)
                .eq("dream_id", value: dreamId)
            // `video_id` is null for gradient cards, and `.eq` can't match null.
            if let videoId {
                try await query.eq("video_id", value: videoId).execute()
            } else {
                try await query.is("video_id", value: nil).execute()
            }
            return true
        } catch {
            print("[LikeRepository] unlike failed: \(error)")
            return false
        }
    }
}
