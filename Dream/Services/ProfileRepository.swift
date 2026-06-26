import Foundation
import Supabase

/// Reads user profiles from Supabase. The profile screen owns its own loaded
/// state, so this is a thin, stateless fetch helper (unlike `DreamRepository`).
@MainActor
final class ProfileRepository {
    static let shared = ProfileRepository()

    private let client = SupabaseService.shared.client
    private init() {}

    /// Fetches a single profile row by `auth.users` id. Returns `nil` if missing
    /// or on failure (the screen falls back to a minimal placeholder).
    func profile(userId: UUID) async -> ProfileDTO? {
        do {
            return try await client
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value
        } catch {
            print("[ProfileRepository] profile(userId:) failed: \(error)")
            return nil
        }
    }

    /// Fetches the aggregate stats (videos / followers / following / offers) for a
    /// profile from the `profile_stats` view. Returns `nil` on failure.
    func stats(userId: UUID) async -> ProfileStatsDTO? {
        do {
            return try await client
                .from("profile_stats")
                .select()
                .eq("profile_id", value: userId)
                .single()
                .execute()
                .value
        } catch {
            print("[ProfileRepository] stats(userId:) failed: \(error)")
            return nil
        }
    }

    /// Updates the current user's profile. `handle` is unique — a collision throws.
    func updateProfile(
        userId: UUID,
        name: String,
        handle: String,
        location: String,
        skills: [String]
    ) async throws {
        let payload = ProfileUpdatePayload(
            name: name.isEmpty ? nil : name,
            handle: handle.isEmpty ? nil : handle,
            location: location.isEmpty ? nil : location,
            skills: skills
        )
        try await client
            .from("profiles")
            .update(payload)
            .eq("id", value: userId)
            .execute()
    }

    /// Sets or clears the current user's profile picture URL. Passing nil clears
    /// it (falls back to the procedural avatar).
    func updateAvatar(userId: UUID, avatarURL: String?) async throws {
        try await client
            .from("profiles")
            .update(AvatarUpdatePayload(avatar_url: avatarURL))
            .eq("id", value: userId)
            .execute()
    }

    // MARK: - Follows

    /// Whether the signed-in user follows `userId`.
    func isFollowing(_ userId: UUID) async -> Bool {
        guard let me = try? await client.auth.session.user.id else { return false }
        do {
            let rows: [FollowPayload] = try await client
                .from("follows")
                .select("follower_id, followed_id")
                .eq("follower_id", value: me)
                .eq("followed_id", value: userId)
                .execute()
                .value
            return !rows.isEmpty
        } catch {
            return false
        }
    }

    /// Profiles the current user follows. Used as the in-app share recipient
    /// list: people you follow are treated as friends.
    func followingProfiles(limit: Int = 80) async -> [ProfileDTO] {
        guard let me = try? await client.auth.session.user.id else { return [] }
        do {
            let follows: [FollowPayload] = try await client
                .from("follows")
                .select("follower_id, followed_id")
                .eq("follower_id", value: me)
                .limit(limit)
                .execute()
                .value
            let ids = follows.map(\.followed_id)
            guard !ids.isEmpty else { return [] }
            return try await client
                .from("profiles")
                .select("id,handle,name,location,skills,avatar_seed,avatar_url")
                .in("id", values: ids)
                .execute()
                .value
        } catch {
            print("[ProfileRepository] followingProfiles failed: \(error)")
            return []
        }
    }

    func follow(_ userId: UUID) async throws {
        let me = try await client.auth.session.user.id
        try await client
            .from("follows")
            .insert(FollowPayload(follower_id: me, followed_id: userId))
            .execute()
    }

    func unfollow(_ userId: UUID) async throws {
        let me = try await client.auth.session.user.id
        try await client
            .from("follows")
            .delete()
            .eq("follower_id", value: me)
            .eq("followed_id", value: userId)
            .execute()
    }
}
