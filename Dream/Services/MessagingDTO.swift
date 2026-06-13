import Foundation

// MARK: - Help offer status

/// The offer lifecycle shown in Activity. Mirrors the `help_offer_status`
/// Postgres enum, mapping the legacy `declined`/`withdrawn` values onto
/// `rejected`/`cancelled` (see migration 0008).
enum HelpOfferStatus: String, CaseIterable, Hashable {
    case pending, accepted, rejected, inProgress, completed, cancelled

    var dbValue: String {
        switch self {
        case .pending:    return "pending"
        case .accepted:   return "accepted"
        case .rejected:   return "rejected"
        case .inProgress: return "in_progress"
        case .completed:  return "completed"
        case .cancelled:  return "cancelled"
        }
    }

    static func from(dbValue raw: String) -> HelpOfferStatus {
        switch raw {
        case "pending":              return .pending
        case "accepted":             return .accepted
        case "rejected", "declined": return .rejected
        case "in_progress":          return .inProgress
        case "completed":            return .completed
        case "cancelled", "withdrawn": return .cancelled
        default:                     return .pending
        }
    }

    var label: String {
        switch self {
        case .pending:    return "Pending"
        case .accepted:   return "Accepted"
        case .rejected:   return "Rejected"
        case .inProgress: return "In Progress"
        case .completed:  return "Completed"
        case .cancelled:  return "Cancelled"
        }
    }

    /// Colour for the status pill, drawn from category palettes for consistency.
    var palette: CategoryPalette {
        switch self {
        case .pending:    return .init(fg: DreamTheme.ink2, bg: DreamTheme.bg, tint: DreamTheme.bg)
        case .accepted:   return DreamCategory.impact.palette
        case .inProgress: return DreamCategory.tech.palette
        case .completed:  return DreamCategory.sport.palette
        case .rejected:   return DreamCategory.health.palette
        case .cancelled:  return .init(fg: DreamTheme.ink3, bg: DreamTheme.line, tint: DreamTheme.bg)
        }
    }

    /// Whether the offer is still live (owner can still act on it).
    var isActive: Bool {
        self == .pending || self == .accepted || self == .inProgress
    }
}

// MARK: - DB row DTOs

struct ConversationDTO: Codable, Hashable {
    let id: UUID
    let dreamId: UUID?
    let lastMessageAt: Date?
    let lastMessagePreview: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case dreamId = "dream_id"
        case lastMessageAt = "last_message_at"
        case lastMessagePreview = "last_message_preview"
        case createdAt = "created_at"
    }
}

struct ConversationParticipantDTO: Codable, Hashable {
    let conversationId: UUID
    let userId: UUID
    let role: String
    let lastReadAt: Date?

    enum CodingKeys: String, CodingKey {
        case role
        case conversationId = "conversation_id"
        case userId = "user_id"
        case lastReadAt = "last_read_at"
    }
}

struct MessageDTO: Codable, Hashable, Identifiable {
    let id: UUID
    let conversationId: UUID
    let senderId: UUID
    let body: String
    let kind: String        // "text" | "system"
    let createdAt: Date

    var isSystem: Bool { kind == "system" }

    enum CodingKeys: String, CodingKey {
        case id, body, kind
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case createdAt = "created_at"
    }
}

struct NotificationDTO: Codable, Hashable, Identifiable {
    let id: UUID
    let userId: UUID
    let type: String
    let actorId: UUID?
    let dreamId: UUID?
    let offerId: UUID?
    let conversationId: UUID?
    let preview: String
    let readAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, type, preview
        case userId = "user_id"
        case actorId = "actor_id"
        case dreamId = "dream_id"
        case offerId = "offer_id"
        case conversationId = "conversation_id"
        case readAt = "read_at"
        case createdAt = "created_at"
    }
}

/// Full help-offer row (extends the read-only `HelpOfferDTO` in DreamDTO.swift
/// with the conversation link added in migration 0008).
struct HelpOfferRow: Codable, Hashable, Identifiable {
    let id: UUID
    let dreamId: UUID
    let supporterId: UUID
    let skill: String
    let message: String
    let status: String
    let conversationId: UUID?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, skill, message, status
        case dreamId = "dream_id"
        case supporterId = "supporter_id"
        case conversationId = "conversation_id"
        case createdAt = "created_at"
    }
}

// MARK: - RPC results & payloads

struct CreateHelpOfferResult: Decodable {
    let offerId: UUID
    let conversationId: UUID
    let alreadyExisted: Bool

    enum CodingKeys: String, CodingKey {
        case offerId = "offer_id"
        case conversationId = "conversation_id"
        case alreadyExisted = "already_existed"
    }
}

struct NewMessagePayload: Encodable {
    let conversation_id: UUID
    let sender_id: UUID
    let body: String
}
