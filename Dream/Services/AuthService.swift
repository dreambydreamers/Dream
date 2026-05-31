import Combine
import Foundation
import Supabase

/// Auth wrapper. For now this uses Supabase's anonymous sign-in to stub a real
/// user identity on the simulator. When Apple Sign-In is added later, the
/// anonymous session can be linked into the Apple identity without losing data.
@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published private(set) var userId: UUID?
    @Published private(set) var isSignedIn = false

    private let client = SupabaseService.shared.client
    private var authListener: Task<Void, Never>?

    private init() {
        authListener = Task { [weak self] in
            guard let stream = await self?.client.auth.authStateChanges else { return }
            for await _ in stream {
                await self?.refresh()
            }
        }
        Task { await refresh() }
    }

    /// Call on app launch. If there's no session, signs in anonymously.
    func ensureSignedIn() async {
        do {
            _ = try await client.auth.session
            await refresh()
        } catch {
            await signInAnonymously()
        }
    }

    func signInAnonymously() async {
        do {
            try await client.auth.signInAnonymously()
            await refresh()
        } catch {
            print("[AuthService] anon sign-in failed: \(error)")
        }
    }

    func signOut() async {
        try? await client.auth.signOut()
        await refresh()
    }

    private func refresh() async {
        let session = try? await client.auth.session
        self.userId = session?.user.id
        self.isSignedIn = session != nil
    }
}
