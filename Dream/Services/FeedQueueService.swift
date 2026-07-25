import Combine
import DreamRanking
import Foundation
import Supabase

/// Owns the precomputed per-viewer feed queue: fetches candidates, runs the
/// pure ranker in the background, persists the result locally, and serves it
/// as a cursor-paginated stream. Refills automatically when fewer than
/// `RankingConfig.queueRefillThreshold` items remain.
///
/// The queue is device-local by design: fairness depends on impressions the
/// server records at display time (EngagementLogger), so losing the queue
/// costs nothing — the next refill simply re-ranks.
@MainActor
final class FeedQueueService: ObservableObject {
    static let shared = FeedQueueService()

    struct QueueEntry: Codable, Identifiable, Equatable {
        let id: UUID // dream id
        let reason: String
        let isFairnessSlot: Bool
        let score: Double
    }

    private struct PersistedQueue: Codable {
        let userId: UUID
        let entries: [QueueEntry]
        let cursor: Int
    }

    var config = RankingConfig.default

    private let client = SupabaseService.shared.client
    private(set) var queue: [QueueEntry] = []
    private var cursor = 0
    private var loadedForUser: UUID?
    private var refillTask: Task<Void, Never>?

    private init() {}

    // MARK: - Serving

    /// The next page of ranked entries, refilling when the queue runs low.
    /// Blocks on a refill only when the queue can't satisfy the page.
    func nextPage(count: Int? = nil) async -> [QueueEntry] {
        let pageSize = count ?? config.pageSize
        await loadIfNeeded()
        if remaining < pageSize {
            await refill()
        }
        let end = min(cursor + pageSize, queue.count)
        guard cursor < end else { return [] }
        let page = Array(queue[cursor..<end])
        cursor = end
        persist()
        if remaining < config.queueRefillThreshold {
            refillSoon()
        }
        return page
    }

    /// Explainability hook for the UI: why is this dream in the feed?
    func reason(for dreamId: UUID) -> String? {
        queue.first { $0.id == dreamId }?.reason
    }

    /// Call on logout: drops the queue and its file.
    func reset() {
        refillTask?.cancel()
        refillTask = nil
        queue = []
        cursor = 0
        if let url = try? storeURL() {
            try? FileManager.default.removeItem(at: url)
        }
        loadedForUser = nil
    }

    // MARK: - Refill (the "background job": fetch → pure rank → persist)

    private var remaining: Int { queue.count - cursor }

    private func refillSoon() {
        guard refillTask == nil else { return }
        refillTask = Task { [weak self] in
            await self?.refill()
            self?.refillTask = nil
        }
    }

    private func refill() async {
        do {
            let repository = RecommendationRepository.shared
            let viewer = try await repository.fetchViewerProfile()
            let candidates = try await repository.fetchCandidates(config: config)
            let ranked = DreamRanker.rank(
                candidates: candidates,
                viewer: viewer,
                config: config,
                now: Date(),
                seed: UInt64(bitPattern: Int64(Date().timeIntervalSince1970))
            )

            // Keep the unserved tail, append fresh items not already queued.
            let unserved = Array(queue[cursor...])
            let queuedIds = Set(unserved.map(\.id))
            let fresh = ranked
                .filter { !queuedIds.contains($0.id) }
                .prefix(max(config.queueTargetLength - unserved.count, 0))
                .map { item in
                    QueueEntry(
                        id: item.id,
                        reason: item.reason,
                        isFairnessSlot: item.isFairnessSlot,
                        score: item.score.total
                    )
                }
            queue = unserved + fresh
            cursor = 0
            loadedForUser = viewer.userId
            persist()
        } catch {
            print("[FeedQueueService] refill failed: \(error)")
        }
    }

    // MARK: - Local persistence (Application Support, per-user file)

    private func storeURL() throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        return directory.appendingPathComponent("feed-queue.json")
    }

    private func persist() {
        guard let userId = loadedForUser else { return }
        let persisted = PersistedQueue(userId: userId, entries: queue, cursor: cursor)
        guard let url = try? storeURL(), let data = try? JSONEncoder().encode(persisted) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func loadIfNeeded() async {
        guard let userId = try? await client.auth.session.user.id else { return }
        guard loadedForUser != userId else { return }
        loadedForUser = userId
        queue = []
        cursor = 0
        guard let url = try? storeURL(),
              let data = try? Data(contentsOf: url),
              let persisted = try? JSONDecoder().decode(PersistedQueue.self, from: data),
              persisted.userId == userId
        else { return }
        queue = persisted.entries
        cursor = min(persisted.cursor, queue.count)
    }
}
