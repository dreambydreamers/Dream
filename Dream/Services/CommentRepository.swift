import Combine
import Foundation
import Supabase

// MARK: - DTOs

struct DreamCommentDTO: Codable, Hashable {
    let id: UUID
    let dreamId: UUID
    let videoId: UUID?
    let userId: UUID
    let body: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, body
        case dreamId = "dream_id"
        case videoId = "video_id"
        case userId = "user_id"
        case createdAt = "created_at"
    }
}

struct DreamCommentCountDTO: Codable, Hashable {
    let dreamId: UUID
    let commentsCount: Int

    enum CodingKeys: String, CodingKey {
        case dreamId = "dream_id"
        case commentsCount = "comments_count"
    }
}

/// Display model: a comment joined with its author's profile.
struct DreamComment: Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    let name: String
    let handle: String
    let avatarSeed: Int
    let avatarURL: URL?
    let body: String
    let createdAt: Date
}

// MARK: - Repository

/// Reads/writes dream comments. Posting also logs a `comment` engagement
/// event, which feeds the commenting viewer's own affinity profile.
@MainActor
final class CommentRepository: ObservableObject {
    static let shared = CommentRepository()

    private let client = SupabaseService.shared.client
    private init() {}

    private enum Columns {
        static let comment = "id,dream_id,video_id,user_id,body,created_at"
        static let profile = "id,handle,name,location,skills,avatar_seed,avatar_url"
        static let count = "dream_id,comments_count"
    }

    /// Oldest-first thread for a dream, with author profiles resolved.
    func comments(forDream dreamId: UUID, limit: Int = 200) async -> [DreamComment] {
        do {
            let rows: [DreamCommentDTO] = try await client
                .from("dream_comments")
                .select(Columns.comment)
                .eq("dream_id", value: dreamId)
                .order("created_at", ascending: true)
                .limit(limit)
                .execute()
                .value

            let userIds = Array(Set(rows.map(\.userId)))
            var profilesById: [UUID: ProfileDTO] = [:]
            if !userIds.isEmpty {
                let profiles: [ProfileDTO] = try await client
                    .from("profiles")
                    .select(Columns.profile)
                    .in("id", values: userIds)
                    .execute()
                    .value
                profilesById = Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            }
            return rows.map { Self.display($0, profile: profilesById[$0.userId]) }
        } catch {
            print("[CommentRepository] comments(forDream:) failed: \(error)")
            return []
        }
    }

    /// Inserts a comment as the signed-in user and returns it ready to display.
    func post(dreamId: UUID, videoId: UUID?, body: String) async throws -> DreamComment {
        guard let userId = try? await client.auth.session.user.id else {
            throw NSError(domain: "CommentRepository", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }
        struct Payload: Encodable {
            let dream_id: UUID
            let video_id: UUID?
            let user_id: UUID
            let body: String
        }
        let inserted: DreamCommentDTO = try await client
            .from("dream_comments")
            .insert(Payload(dream_id: dreamId, video_id: videoId, user_id: userId, body: body),
                    returning: .representation)
            .select(Columns.comment)
            .single()
            .execute()
            .value

        EngagementLogger.shared.log(.comment, dreamId: dreamId)

        let profile: ProfileDTO? = try? await client
            .from("profiles")
            .select(Columns.profile)
            .eq("id", value: userId)
            .single()
            .execute()
            .value
        return Self.display(inserted, profile: profile)
    }

    /// RLS allows the author or the dream owner to delete.
    func delete(_ commentId: UUID) async throws {
        try await client
            .from("dream_comments")
            .delete()
            .eq("id", value: commentId)
            .execute()
    }

    /// Comment counts for a batch of dreams (feed badges).
    func counts(forDreams dreamIds: [UUID]) async -> [UUID: Int] {
        guard !dreamIds.isEmpty else { return [:] }
        do {
            let rows: [DreamCommentCountDTO] = try await client
                .from("dream_comment_counts")
                .select(Columns.count)
                .in("dream_id", values: dreamIds)
                .execute()
                .value
            return Dictionary(rows.map { ($0.dreamId, $0.commentsCount) }, uniquingKeysWith: { a, _ in a })
        } catch {
            print("[CommentRepository] counts(forDreams:) failed: \(error)")
            return [:]
        }
    }

    private static func display(_ row: DreamCommentDTO, profile: ProfileDTO?) -> DreamComment {
        DreamComment(
            id: row.id,
            userId: row.userId,
            name: profile?.name ?? "Anonymous",
            handle: profile?.handle ?? "anon",
            avatarSeed: profile?.avatarSeed ?? 0,
            avatarURL: profile?.avatarURLValue,
            body: row.body,
            createdAt: row.createdAt
        )
    }
}
