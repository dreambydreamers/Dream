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
}
