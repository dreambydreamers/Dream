import Foundation
import Supabase

/// In-app video sharing. The backend RPC creates/reuses a direct 1:1
/// conversation, inserts a structured `dream_share` message, and lets the
/// existing message trigger notify the recipient in Activity.
@MainActor
final class VideoShareRepository {
    static let shared = VideoShareRepository()

    private let client = SupabaseService.shared.client
    private init() {}

    private struct ShareParams: Encodable {
        let p_recipient_id: UUID
        let p_dream_id: UUID
        let p_video_id: UUID?
        let p_note: String
    }

    @discardableResult
    func share(dream: Dream, recipientId: UUID, note: String = "") async throws -> ShareDreamVideoResult {
        let rows: [ShareDreamVideoResult] = try await client
            .rpc("share_dream_video", params: ShareParams(
                p_recipient_id: recipientId,
                p_dream_id: dream.id,
                p_video_id: dream.videoId,
                p_note: note
            ))
            .execute()
            .value
        guard let first = rows.first else {
            throw NSError(domain: "VideoShareRepository", code: 500,
                          userInfo: [NSLocalizedDescriptionKey: "share_dream_video returned no row"])
        }
        return first
    }
}
