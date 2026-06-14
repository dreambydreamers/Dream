import Combine
import Foundation
import Supabase

/// Drives a single conversation: loads history, sends messages, and keeps the
/// thread live over Supabase Realtime — message inserts (postgres changes),
/// typing indicators (broadcast), online status (presence) and read receipts
/// (the other participant's `last_read_at`, via a participants UPDATE stream).
///
/// One instance per open `ChatScreen`; `start()` on appear, `stop()` on disappear.
@MainActor
final class ChatRepository: ObservableObject {
    @Published private(set) var messages: [MessageDTO] = []
    @Published private(set) var otherLastReadAt: Date?
    @Published private(set) var isOtherOnline = false
    @Published private(set) var isOtherTyping = false
    @Published private(set) var isLoading = false
    @Published var draft: String = ""

    let conversationId: UUID
    let me: UUID
    let otherUserId: UUID

    private let client = SupabaseService.shared.client
    private let decoder = PostgrestClient.Configuration.jsonDecoder

    private var channel: RealtimeChannelV2?
    private var streamTasks: [Task<Void, Never>] = []
    private var typingResetTask: Task<Void, Never>?
    private var markReadTask: Task<Void, Never>?
    private var lastTypingSentAt: Date = .distantPast
    private var onlineUserIds: Set<String> = []

    init(conversationId: UUID, me: UUID, otherUserId: UUID) {
        self.conversationId = conversationId
        self.me = me
        self.otherUserId = otherUserId
    }

    private struct PresencePayload: Codable { let user_id: String }

    // MARK: - Lifecycle

    func start() async {
        await loadMessages()
        await markRead()
        await subscribe()
    }

    func stop() async {
        typingResetTask?.cancel()
        markReadTask?.cancel(); markReadTask = nil
        streamTasks.forEach { $0.cancel() }
        streamTasks.removeAll()
        if let channel {
            await channel.unsubscribe()
            await client.removeChannel(channel)
        }
        channel = nil
    }

    // MARK: - Load

    func loadMessages() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let msgs: [MessageDTO] = client
                .from("messages")
                .select()
                .eq("conversation_id", value: conversationId)
                .order("created_at", ascending: true)
                .execute().value
            async let parts: [ConversationParticipantDTO] = client
                .from("conversation_participants")
                .select()
                .eq("conversation_id", value: conversationId)
                .execute().value

            let (m, p) = try await (msgs, parts)
            self.messages = m
            self.otherLastReadAt = p.first(where: { $0.userId == otherUserId })?.lastReadAt
        } catch {
            print("[ChatRepository] loadMessages failed: \(error)")
        }
    }

    // MARK: - Send

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        do {
            // Insert and append immediately for snappiness; the realtime echo is
            // de-duplicated by id in `append(_:)`.
            let inserted: MessageDTO = try await client
                .from("messages")
                .insert(NewMessagePayload(conversation_id: conversationId, sender_id: me, body: text),
                        returning: .representation)
                .select()
                .single()
                .execute().value
            append(inserted)
        } catch {
            print("[ChatRepository] send failed: \(error)")
            draft = text   // restore so the user doesn't lose their message
        }
    }

    func markRead() async {
        struct Param: Encodable { let p_conversation_id: UUID }
        do {
            try await client
                .rpc("mark_conversation_read", params: Param(p_conversation_id: conversationId))
                .execute()
        } catch {
            print("[ChatRepository] markRead failed: \(error)")
        }
    }

    /// Coalesces read receipts. A rapid burst of incoming messages otherwise
    /// fires one `mark_conversation_read` RPC per message; debouncing collapses
    /// the burst into ~1 RPC.
    private func scheduleMarkRead() {
        markReadTask?.cancel()
        markReadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.markRead()
        }
    }

    /// Throttled typing ping (broadcast is ephemeral; ~3s between sends).
    func notifyTyping() {
        let now = Date()
        guard now.timeIntervalSince(lastTypingSentAt) > 3.0, let channel else { return }
        lastTypingSentAt = now
        Task { await channel.broadcast(event: "typing", message: ["user_id": .string(me.uuidString)]) }
    }

    // MARK: - Realtime

    private func subscribe() async {
        let ch = client.channel("conversation:\(conversationId.uuidString)")
        self.channel = ch

        let inserts = ch.postgresChange(InsertAction.self, schema: "public", table: "messages",
                                        filter: .eq("conversation_id", value: conversationId))
        let readUpdates = ch.postgresChange(UpdateAction.self, schema: "public", table: "conversation_participants",
                                            filter: .eq("conversation_id", value: conversationId))
        let typing = ch.broadcastStream(event: "typing")
        let presence = ch.presenceChange()

        try? await ch.subscribeWithError()
        await ch.track(state: ["user_id": .string(me.uuidString)])

        streamTasks = [
            Task { [weak self] in
                for await change in inserts {
                    guard let self else { break }
                    if let msg = try? change.decodeRecord(as: MessageDTO.self, decoder: self.decoder) {
                        self.append(msg)
                        if msg.senderId != self.me { self.scheduleMarkRead() }
                    }
                }
            },
            Task { [weak self] in
                for await change in readUpdates {
                    guard let self else { break }
                    if let p = try? change.decodeRecord(as: ConversationParticipantDTO.self, decoder: self.decoder),
                       p.userId == self.otherUserId {
                        self.otherLastReadAt = p.lastReadAt
                    }
                }
            },
            Task { [weak self] in
                for await payload in typing {
                    guard let self else { break }
                    if payload["user_id"]?.stringValue != self.me.uuidString {
                        self.flashTyping()
                    }
                }
            },
            Task { [weak self] in
                for await change in presence {
                    guard let self else { break }
                    let joined = (try? change.decodeJoins(as: PresencePayload.self)) ?? []
                    let left = (try? change.decodeLeaves(as: PresencePayload.self)) ?? []
                    for j in joined { self.onlineUserIds.insert(j.user_id) }
                    for l in left { self.onlineUserIds.remove(l.user_id) }
                    self.isOtherOnline = self.onlineUserIds.contains(self.otherUserId.uuidString)
                }
            }
        ]
    }

    // MARK: - Helpers

    private func append(_ msg: MessageDTO) {
        guard !messages.contains(where: { $0.id == msg.id }) else { return }
        messages.append(msg)
        messages.sort { $0.createdAt < $1.createdAt }
    }

    private func flashTyping() {
        isOtherTyping = true
        typingResetTask?.cancel()
        typingResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.isOtherTyping = false
        }
    }
}
