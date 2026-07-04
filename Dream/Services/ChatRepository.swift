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
    @Published private(set) var sharedPreviews: [UUID: SharedVideoPreview] = [:]
    @Published private(set) var otherLastReadAt: Date?
    @Published private(set) var isOtherOnline = false
    @Published private(set) var isOtherTyping = false
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
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
    private struct SharedDreamRow: Codable {
        let id: UUID
        let title: String
        let category: String
    }
    private struct SharedVideoRow: Codable {
        let id: UUID
        let dreamId: UUID
        let posterPath: String?
        let title: String?

        enum CodingKeys: String, CodingKey {
            case id, title
            case dreamId = "dream_id"
            case posterPath = "poster_path"
        }
    }

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
                .select("id,conversation_id,sender_id,body,kind,shared_dream_id,shared_video_id,created_at")
                .eq("conversation_id", value: conversationId)
                .order("created_at", ascending: false)
                .limit(200)
                .execute().value
            async let parts: [ConversationParticipantDTO] = client
                .from("conversation_participants")
                .select("conversation_id,user_id,role,last_read_at")
                .eq("conversation_id", value: conversationId)
                .execute().value

            let (m, p) = try await (msgs, parts)
            self.messages = Array(m.reversed())
            self.otherLastReadAt = p.first(where: { $0.userId == otherUserId })?.lastReadAt
            await loadSharePreviews(for: m)
            lastError = nil
        } catch {
            lastError = "\(error)"
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
                .select("id,conversation_id,sender_id,body,kind,shared_dream_id,shared_video_id,created_at")
                .single()
                .execute().value
            append(inserted)
            lastError = nil
        } catch {
            lastError = "\(error)"
            print("[ChatRepository] send failed: \(error)")
            if draft.isEmpty {
                draft = text
            }
        }
    }

    func markRead() async {
        struct Param: Encodable { let p_conversation_id: UUID }
        do {
            try await client
                .rpc("mark_conversation_read", params: Param(p_conversation_id: conversationId))
                .execute()
        } catch {
            lastError = "\(error)"
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
        // Private channel: broadcast/presence are gated by the realtime.messages
        // policies from migration 0019 (participants only).
        let ch = client.channel("conversation:\(conversationId.uuidString)") {
            $0.isPrivate = true
        }
        self.channel = ch

        let inserts = ch.postgresChange(InsertAction.self, schema: "public", table: "messages",
                                        filter: .eq("conversation_id", value: conversationId))
        let readUpdates = ch.postgresChange(UpdateAction.self, schema: "public", table: "conversation_participants",
                                            filter: .eq("conversation_id", value: conversationId))
        let typing = ch.broadcastStream(event: "typing")
        let presence = ch.presenceChange()

        do {
            try await ch.subscribeWithError()
        } catch {
            print("[ChatRepository] channel subscribe failed: \(error)")
        }
        await ch.track(state: ["user_id": .string(me.uuidString)])

        streamTasks = [
            Task { [weak self] in
                for await change in inserts {
                    guard let self else { break }
                    if let msg = try? change.decodeRecord(as: MessageDTO.self, decoder: self.decoder) {
                        self.append(msg)
                        if msg.isDreamShare { await self.loadSharePreviews(for: [msg]) }
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

    private func loadSharePreviews(for messages: [MessageDTO]) async {
        let shareMessages = messages.filter(\.isDreamShare)
        let dreamIds = Array(Set(shareMessages.compactMap(\.sharedDreamId)))
        let videoIds = Array(Set(shareMessages.compactMap(\.sharedVideoId)))
        guard !dreamIds.isEmpty else { return }

        do {
            async let dreams: [SharedDreamRow] = client
                .from("dreams")
                .select("id,title,category")
                .in("id", values: dreamIds)
                .execute()
                .value
            async let videos: [SharedVideoRow] = videoIds.isEmpty ? [] : client
                .from("dream_videos")
                .select("id,dream_id,poster_path,title")
                .in("id", values: videoIds)
                .execute()
                .value

            let (dreamRows, videoRows) = try await (dreams, videos)
            let dreamById = Dictionary(dreamRows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let videoById = Dictionary(videoRows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

            var next = sharedPreviews
            for message in shareMessages {
                guard let dreamId = message.sharedDreamId, let dream = dreamById[dreamId] else { continue }
                let video = message.sharedVideoId.flatMap { videoById[$0] }
                let key = message.sharedVideoId ?? dreamId
                let posterURL = video?.posterPath.flatMap { path in
                    try? client.storage.from("dream-posters").getPublicURL(path: path)
                }
                next[key] = SharedVideoPreview(
                    dreamId: dreamId,
                    videoId: message.sharedVideoId,
                    title: video?.title ?? dream.title,
                    category: DreamCategory.from(dbValue: dream.category),
                    posterURL: posterURL
                )
            }
            sharedPreviews = next
        } catch {
            print("[ChatRepository] loadSharePreviews failed: \(error)")
        }
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
