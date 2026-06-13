import Combine
import Foundation
import Supabase

// MARK: - Activity view models

struct ActivityNotification: Identifiable, Hashable {
    let id: UUID
    let type: String
    let preview: String
    let actorName: String
    let actorSeed: Int
    let actorId: UUID?
    let conversationId: UUID?
    let createdAt: Date
    let isRead: Bool

    var icon: String {
        switch type {
        case "offer_received":    return "hand.raised.fill"
        case "offer_accepted":    return "checkmark.seal.fill"
        case "offer_rejected":    return "xmark.seal.fill"
        case "offer_in_progress": return "hammer.fill"
        case "offer_completed":   return "flag.checkered"
        case "offer_cancelled":   return "slash.circle"
        case "new_message":       return "bubble.left.fill"
        default:                  return "bell.fill"
        }
    }
}

struct ConversationSummary: Identifiable, Hashable {
    let id: UUID
    let otherUserId: UUID
    let otherName: String
    let otherSeed: Int
    let dreamId: UUID?
    let preview: String
    let lastMessageAt: Date?
    let unread: Bool
}

struct OfferSummary: Identifiable, Hashable {
    let id: UUID
    let dreamId: UUID
    let dreamTitle: String
    let counterpartId: UUID
    let counterpartName: String
    let counterpartSeed: Int
    let skill: String
    let message: String
    let status: HelpOfferStatus
    let conversationId: UUID?
    let createdAt: Date
    /// True when this offer came in on one of my dreams (I'm the owner); false
    /// when I made it on someone else's dream.
    let incoming: Bool
}

/// Aggregates everything the Activity tab shows — notifications, conversations
/// and help offers (made & received) — and keeps an `unreadCount` for the tab
/// bar badge live over Realtime. App-wide singleton: `start()` once signed in.
@MainActor
final class ActivityRepository: ObservableObject {
    static let shared = ActivityRepository()

    @Published private(set) var notifications: [ActivityNotification] = []
    @Published private(set) var conversations: [ConversationSummary] = []
    @Published private(set) var offersReceived: [OfferSummary] = []
    @Published private(set) var offersMade: [OfferSummary] = []
    @Published private(set) var unreadCount = 0
    @Published private(set) var isLoading = false

    private let client = SupabaseService.shared.client
    private var channel: RealtimeChannelV2?
    private var streamTask: Task<Void, Never>?
    private var startedFor: UUID?

    private init() {}

    private struct DreamLite: Codable { let id: UUID; let title: String; let ownerId: UUID
        enum CodingKeys: String, CodingKey { case id, title; case ownerId = "owner_id" } }

    // MARK: - Lifecycle

    /// Subscribes to this user's notification stream and does an initial load.
    /// Safe to call repeatedly; re-subscribes if the signed-in user changed.
    func start() async {
        guard let me = AuthService.shared.userId else { return }
        if startedFor == me, channel != nil { await load(); return }
        await stop()
        startedFor = me
        await load()
        await subscribe(me: me)
    }

    func stop() async {
        streamTask?.cancel(); streamTask = nil
        if let channel { await channel.unsubscribe(); await client.removeChannel(channel) }
        channel = nil
        startedFor = nil
    }

    // MARK: - Load

    func load() async {
        guard let me = AuthService.shared.userId else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            // Phase 1: independent fetches.
            async let notifRows: [NotificationDTO] = client
                .from("notifications").select().eq("user_id", value: me)
                .order("created_at", ascending: false).limit(60).execute().value
            async let myParts: [ConversationParticipantDTO] = client
                .from("conversation_participants").select().eq("user_id", value: me).execute().value
            async let made: [HelpOfferRow] = client
                .from("help_offers").select().eq("supporter_id", value: me)
                .order("created_at", ascending: false).execute().value
            async let myDreams: [DreamLite] = client
                .from("dreams").select("id,title,owner_id").eq("owner_id", value: me).execute().value

            let (notifs, parts, offersMadeRows, dreamsOwned) = try await (notifRows, myParts, made, myDreams)

            // Phase 2: depends on phase 1 ids.
            let convIds = parts.map(\.conversationId)
            let myDreamIds = dreamsOwned.map(\.id)

            async let convRows: [ConversationDTO] = convIds.isEmpty ? [] : client
                .from("conversations").select().in("id", values: convIds).execute().value
            async let allPartRows: [ConversationParticipantDTO] = convIds.isEmpty ? [] : client
                .from("conversation_participants").select().in("conversation_id", values: convIds).execute().value
            async let received: [HelpOfferRow] = myDreamIds.isEmpty ? [] : client
                .from("help_offers").select().in("dream_id", values: myDreamIds)
                .order("created_at", ascending: false).execute().value

            let (convs, allParts, offersReceivedRows) = try await (convRows, allPartRows, received)

            // Phase 3: resolve every referenced profile + dream title in one go.
            let offerDreamIds = Set(offersMadeRows.map(\.dreamId) + offersReceivedRows.map(\.dreamId))
            var profileIds = Set<UUID>()
            notifs.forEach { if let a = $0.actorId { profileIds.insert(a) } }
            allParts.forEach { if $0.userId != me { profileIds.insert($0.userId) } }
            offersReceivedRows.forEach { profileIds.insert($0.supporterId) }

            async let profileRows: [ProfileDTO] = profileIds.isEmpty ? [] : client
                .from("profiles").select().in("id", values: Array(profileIds)).execute().value
            async let offerDreamRows: [DreamLite] = offerDreamIds.isEmpty ? [] : client
                .from("dreams").select("id,title,owner_id").in("id", values: Array(offerDreamIds)).execute().value

            let (profiles, offerDreams) = try await (profileRows, offerDreamRows)

            let profileById = Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            var dreamById = Dictionary(offerDreams.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for d in dreamsOwned where dreamById[d.id] == nil { dreamById[d.id] = d }

            // ---- assemble ----
            self.notifications = notifs.map { n in
                let p = n.actorId.flatMap { profileById[$0] }
                return ActivityNotification(
                    id: n.id, type: n.type, preview: n.preview,
                    actorName: p?.name ?? "Someone", actorSeed: p?.avatarSeed ?? 0,
                    actorId: n.actorId, conversationId: n.conversationId,
                    createdAt: n.createdAt, isRead: n.readAt != nil)
            }
            self.unreadCount = notifs.reduce(0) { $0 + ($1.readAt == nil ? 1 : 0) }

            let convById = Dictionary(convs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let partsByConv = Dictionary(grouping: allParts, by: \.conversationId)
            self.conversations = parts.compactMap { mine -> ConversationSummary? in
                guard let conv = convById[mine.conversationId] else { return nil }
                let other = partsByConv[conv.id]?.first(where: { $0.userId != me })
                let op = other.flatMap { profileById[$0.userId] }
                let unread: Bool = {
                    guard let last = conv.lastMessageAt else { return false }
                    guard let read = mine.lastReadAt else { return true }
                    return last > read
                }()
                return ConversationSummary(
                    id: conv.id,
                    otherUserId: other?.userId ?? me,
                    otherName: op?.name ?? "Someone",
                    otherSeed: op?.avatarSeed ?? 0,
                    dreamId: conv.dreamId,
                    preview: conv.lastMessagePreview ?? "",
                    lastMessageAt: conv.lastMessageAt,
                    unread: unread)
            }
            .sorted { ($0.lastMessageAt ?? .distantPast) > ($1.lastMessageAt ?? .distantPast) }

            self.offersMade = offersMadeRows.map { row in
                let d = dreamById[row.dreamId]
                let owner = d.flatMap { profileById[$0.ownerId] }
                return OfferSummary(
                    id: row.id, dreamId: row.dreamId, dreamTitle: d?.title ?? "a dream",
                    counterpartId: d?.ownerId ?? row.supporterId,
                    counterpartName: owner?.name ?? "Dreamer", counterpartSeed: owner?.avatarSeed ?? 0,
                    skill: row.skill, message: row.message,
                    status: .from(dbValue: row.status), conversationId: row.conversationId,
                    createdAt: row.createdAt, incoming: false)
            }
            self.offersReceived = offersReceivedRows.map { row in
                let sup = profileById[row.supporterId]
                return OfferSummary(
                    id: row.id, dreamId: row.dreamId, dreamTitle: dreamById[row.dreamId]?.title ?? "your dream",
                    counterpartId: row.supporterId,
                    counterpartName: sup?.name ?? "Someone", counterpartSeed: sup?.avatarSeed ?? 0,
                    skill: row.skill, message: row.message,
                    status: .from(dbValue: row.status), conversationId: row.conversationId,
                    createdAt: row.createdAt, incoming: true)
            }
        } catch {
            print("[ActivityRepository] load failed: \(error)")
        }
    }

    func markAllRead() async {
        do {
            try await client.rpc("mark_all_notifications_read").execute()
            await load()
        } catch {
            print("[ActivityRepository] markAllRead failed: \(error)")
        }
    }

    // MARK: - Realtime

    private func subscribe(me: UUID) async {
        let ch = client.channel("activity:\(me.uuidString)")
        self.channel = ch
        let inserts = ch.postgresChange(InsertAction.self, schema: "public", table: "notifications",
                                        filter: .eq("user_id", value: me))
        let updates = ch.postgresChange(UpdateAction.self, schema: "public", table: "notifications",
                                        filter: .eq("user_id", value: me))
        await ch.subscribe()
        streamTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { for await _ in inserts { await self?.load() } }
                group.addTask { for await _ in updates { await self?.load() } }
            }
        }
    }
}
