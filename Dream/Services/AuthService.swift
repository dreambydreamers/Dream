import Combine
import Foundation
import Supabase

/// Email + password auth backed by Supabase. Restores an existing session on
/// launch and exposes sign-up / sign-in / sign-out for the onboarding flow.
@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published private(set) var userId: UUID?
    @Published private(set) var isSignedIn = false

    /// True while a sign-in / sign-up request is in flight (drives button spinners).
    @Published private(set) var isBusy = false
    /// User-facing message for the most recent failure; cleared on the next attempt.
    @Published var errorMessage: String?
    /// Set when a sign-up succeeds but no session is returned because the project
    /// requires email confirmation. The UI shows a "check your inbox" state.
    @Published var awaitingEmailConfirmation = false

    private let client = SupabaseService.shared.client
    private var authListener: Task<Void, Never>?

    private init() {
        authListener = Task { [weak self] in
            guard let stream = self?.client.auth.authStateChanges else { return }
            for await change in stream {
                if change.event == .initialSession, change.session?.isExpired == true {
                    await self?.refresh()
                } else {
                    self?.apply(session: change.session)
                }
            }
        }
    }

    /// Call on app launch. Restores any persisted session; does nothing if there
    /// isn't one (the onboarding gate then asks the user to sign in).
    func restoreSession() async {
        await refresh()
    }

    func signIn(email: String, password: String) async {
        await run {
            try await self.client.auth.signIn(
                email: email.trimmedLowercased,
                password: password
            )
        }
    }

    func signUp(email: String, password: String, name: String, handle: String) async {
        let trimmedHandle = handle.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        await run {
            let response = try await self.client.auth.signUp(
                email: email.trimmedLowercased,
                password: password,
                data: [
                    "name": .string(trimmedName),
                    "handle": .string(trimmedHandle)
                ]
            )
            // No session means the project requires email confirmation.
            if response.session == nil {
                self.awaitingEmailConfirmation = true
            }
        }
    }

    func signOut() async {
        await run {
            try await self.client.auth.signOut()
        }
    }

    /// Wraps an auth call with busy/error bookkeeping and a session refresh.
    private func run(_ work: @escaping () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        awaitingEmailConfirmation = false
        defer { isBusy = false }
        do {
            try await work()
            await refresh()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private func refresh() async {
        let session = try? await client.auth.session
        apply(session: session)
    }

    private func apply(session: Session?) {
        self.userId = session?.user.id
        self.isSignedIn = session != nil
    }

    private static func message(for error: Error) -> String {
        if let authError = error as? AuthError {
            return authError.message
        }
        return error.localizedDescription
    }
}

private extension String {
    var trimmedLowercased: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
