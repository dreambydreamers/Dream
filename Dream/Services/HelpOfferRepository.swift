import Foundation
import Supabase

/// Writes help offers through the SECURITY DEFINER RPCs (migration 0010), which
/// atomically create the offer, open a conversation, post a system message and
/// notify the other party. A thin, stateless helper like `ProfileRepository`.
@MainActor
final class HelpOfferRepository {
    static let shared = HelpOfferRepository()

    private let client = SupabaseService.shared.client
    private init() {}

    private struct CreateParams: Encodable {
        let p_dream_id: UUID
        let p_skill: String
        let p_message: String
    }

    /// The "I can help" action. Returns the (possibly pre-existing) offer +
    /// conversation; `alreadyExisted` is true when the user had an active offer.
    @discardableResult
    func createOffer(dreamId: UUID, skill: String, message: String) async throws -> CreateHelpOfferResult {
        let rows: [CreateHelpOfferResult] = try await client
            .rpc("create_help_offer",
                 params: CreateParams(p_dream_id: dreamId, p_skill: skill, p_message: message))
            .execute()
            .value
        guard let first = rows.first else {
            throw NSError(domain: "HelpOfferRepository", code: 500,
                          userInfo: [NSLocalizedDescriptionKey: "create_help_offer returned no row"])
        }
        return first
    }

    private struct RespondParams: Encodable {
        let p_offer_id: UUID
        let p_status: String
    }

    /// Dream owner advances an offer (accept / reject / in progress / complete).
    func respond(offerId: UUID, status: HelpOfferStatus) async throws {
        try await client
            .rpc("respond_to_help_offer",
                 params: RespondParams(p_offer_id: offerId, p_status: status.dbValue))
            .execute()
    }

    private struct OfferIdParam: Encodable { let p_offer_id: UUID }

    /// Supporter withdraws their own offer.
    func cancel(offerId: UUID) async throws {
        try await client
            .rpc("cancel_help_offer", params: OfferIdParam(p_offer_id: offerId))
            .execute()
    }
}
