import Combine
import Foundation
import Supabase

// MARK: - Report vocabulary

/// What a report points at. Mirrors the `report_target_type` Postgres enum.
enum ReportTarget: String, Codable {
    case dream
    case video
    case photo
    case comment
    case message
    case profile
}

/// Mirrors the `report_reason` Postgres enum. `label` is what the user picks
/// from; the raw value is what the database stores.
enum ReportReason: String, CaseIterable, Identifiable, Codable {
    case spam
    case harassment
    case hate
    case violence
    case sexualContent = "sexual_content"
    case selfHarm = "self_harm"
    case misinformation
    case impersonation
    case intellectualProperty = "intellectual_property"
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .spam:                 return "Spam or scam"
        case .harassment:           return "Bullying or harassment"
        case .hate:                 return "Hate speech or symbols"
        case .violence:             return "Violence or dangerous acts"
        case .sexualContent:        return "Nudity or sexual content"
        case .selfHarm:             return "Suicide or self-harm"
        case .misinformation:       return "False information"
        case .impersonation:        return "Pretending to be someone else"
        case .intellectualProperty: return "Intellectual property"
        case .other:                return "Something else"
        }
    }

    /// Shown under the label so people pick the right bucket.
    var detail: String {
        switch self {
        case .spam:                 return "Repetitive posts, fake offers, or links to scams."
        case .harassment:           return "Targeted insults, threats, or unwanted contact."
        case .hate:                 return "Attacks based on identity."
        case .violence:             return "Threats, graphic violence, or dangerous challenges."
        case .sexualContent:        return "Sexual content, or any content involving a minor."
        case .selfHarm:             return "We'll also share support resources."
        case .misinformation:       return "Misleading claims presented as fact."
        case .impersonation:        return "Someone posing as you or another person."
        case .intellectualProperty: return "Someone using your work without permission."
        case .other:                return "Tell us what's wrong."
        }
    }
}

// MARK: - DTOs

/// A profile the signed-in user has blocked. Comes from `list_blocked_profiles`
/// rather than a `profiles` read, because a block hides the profile row from
/// the blocker too — see migration 0037.
struct BlockedProfile: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String?
    let handle: String?
    let avatarSeed: Int
    let avatarUrl: String?
    let blockedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, handle
        case avatarSeed = "avatar_seed"
        case avatarUrl  = "avatar_url"
        case blockedAt  = "blocked_at"
    }

    var displayName: String { name ?? "Someone" }
    var displayHandle: String { handle ?? "anon" }
    var avatarURL: URL? { avatarUrl.flatMap(URL.init(string:)) }
}

// MARK: - Repository

/// Blocking and reporting.
///
/// Enforcement lives in the database (migrations 0036/0037): blocking hides
/// both users' content from each other and refuses messages, offers, follows,
/// comments and likes between them. This type is the client's view of that —
/// it drives the UI and keeps a local set of blocked ids so the app can hide
/// content it has already loaded without waiting for a refetch.
@MainActor
final class ModerationRepository: ObservableObject {
    static let shared = ModerationRepository()

    /// Users the signed-in viewer has blocked. Used to filter already-loaded
    /// content immediately; the server enforces the same thing on every fetch.
    @Published private(set) var blockedUserIds: Set<UUID> = []
    /// Targets the viewer has already reported, so the UI can say so instead of
    /// hitting the one-report-per-target unique constraint.
    @Published private(set) var reportedTargetIds: Set<UUID> = []

    private let client = SupabaseService.shared.client
    private var hasLoaded = false

    private init() {}

    // MARK: - Blocks

    func isBlocked(_ userId: UUID) -> Bool { blockedUserIds.contains(userId) }

    /// Loads the viewer's block list once per session.
    func loadBlocksIfNeeded() async {
        guard !hasLoaded else { return }
        await loadBlocks()
    }

    func loadBlocks() async {
        struct Row: Decodable { let blockedId: UUID
            enum CodingKeys: String, CodingKey { case blockedId = "blocked_id" } }
        do {
            let rows: [Row] = try await client
                .from("user_blocks")
                .select("blocked_id")
                .limit(500)
                .execute()
                .value
            blockedUserIds = Set(rows.map(\.blockedId))
            hasLoaded = true
        } catch {
            print("[ModerationRepository] loadBlocks failed: \(error)")
        }
    }

    /// Blocks a user. Goes through the `block_user` RPC rather than a direct
    /// insert so the server can also drop any follow edge in either direction.
    func block(_ userId: UUID) async throws {
        struct Param: Encodable { let p_user_id: UUID }
        try await client.rpc("block_user", params: Param(p_user_id: userId)).execute()
        blockedUserIds.insert(userId)
        // The blocked user's cards may already be on screen and in the ranked
        // queue; drop them so the block looks immediate.
        DreamRepository.shared.removeContent(ownedBy: userId)
        ExploreMediaRepository.shared.removeContent(ownedBy: userId)
    }

    func unblock(_ userId: UUID) async throws {
        try await client
            .from("user_blocks")
            .delete()
            .eq("blocked_id", value: userId)
            .execute()
        blockedUserIds.remove(userId)
    }

    func blockedProfiles() async -> [BlockedProfile] {
        do {
            return try await client.rpc("list_blocked_profiles").execute().value
        } catch {
            print("[ModerationRepository] blockedProfiles failed: \(error)")
            return []
        }
    }

    // MARK: - Reports

    func hasReported(_ targetId: UUID) -> Bool { reportedTargetIds.contains(targetId) }

    /// Files a report. `excerpt` snapshots the reported text so a moderator can
    /// still see it after the author deletes the content.
    func report(
        target: ReportTarget,
        targetId: UUID,
        reportedUserId: UUID?,
        reason: ReportReason,
        note: String?,
        excerpt: String?
    ) async throws {
        guard let reporterId = try? await client.auth.session.user.id else {
            throw NSError(domain: "ModerationRepository", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }
        struct Payload: Encodable {
            let reporter_id: UUID
            let reported_user_id: UUID?
            let target_type: String
            let target_id: UUID
            let reason: String
            let note: String?
            let content_excerpt: String?
        }
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await client
                .from("content_reports")
                .insert(Payload(
                    reporter_id: reporterId,
                    reported_user_id: reportedUserId,
                    target_type: target.rawValue,
                    target_id: targetId,
                    reason: reason.rawValue,
                    note: (trimmedNote?.isEmpty ?? true) ? nil : String(trimmedNote!.prefix(1000)),
                    content_excerpt: excerpt.map { String($0.prefix(2000)) }
                ))
                .execute()
        } catch {
            // A duplicate is the unique (reporter, target_type, target_id)
            // constraint: they already reported this. Not an error worth
            // surfacing — the outcome they wanted is already true.
            guard "\(error)".contains("content_reports_reporter_id_target_type_target_id_key") else {
                throw error
            }
        }
        reportedTargetIds.insert(targetId)
    }

    // MARK: - Session

    /// Clears per-user moderation state on sign-out.
    func reset() {
        blockedUserIds = []
        reportedTargetIds = []
        hasLoaded = false
    }
}
