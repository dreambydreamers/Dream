import Foundation
@testable import DreamRanking

/// In-memory reference implementation of the server side: the dream_seen /
/// dream_exposure_counters trigger semantics and the get_feed_candidates CTE
/// rules (sources, caps, exclusions). Simulation tests drive the REAL
/// `DreamRanker.rank` against this state, so the pipeline is exercised
/// end-to-end without a database.
///
/// Serving mirrors the shipped path (FeedQueueService + DreamRepository
/// .loadRankedFeed + DiscoverScreen): each viewer owns a persistent queue;
/// a session draws `sessionPageSize` entries (blocking refill when the queue
/// can't cover the draw, background refill below `queueRefillThreshold`,
/// refills keep the unserved tail and top up to `queueTargetLength`); the
/// viewer then BROWSES only a prefix of the draw — impressions are recorded
/// for browsed cards only, exactly like DiscoverScreen's view logging.
///
/// Keep the rules here in sync with supabase/migrations/0022 and 0024, and
/// the serving constants with FeedQueueService/DreamRepository.
final class FeedSimulation {

    /// DreamRepository.loadRankedFeed's page draw.
    static let sessionPageSize = 50

    struct SimDream {
        let id: UUID
        let ownerId: UUID
        let category: String
        let stage: String
        let location: String?
        let helpTags: [String]
        let helpTypes: Set<HelpType>
        let createdAt: Date
    }

    struct SeenEntry {
        var firstSeenAt: Date
        var lastSeenAt: Date
        var seenCount: Int
        var dismissed: Bool
    }

    var config: RankingConfig
    private(set) var now: Date
    private(set) var dreams: [SimDream]
    let viewers: [ViewerProfile]

    // Server-side state mirrors.
    private(set) var seen: [UUID: [UUID: SeenEntry]] = [:]          // viewer -> dream -> entry
    private(set) var impressions: [UUID: Int] = [:]                  // dream -> count
    private(set) var distinctViewers: [UUID: Set<UUID>] = [:]        // dream -> viewer ids
    private(set) var offersReceived: [UUID: Int] = [:]               // dream -> count
    /// Viewer-local affinity points (mirror of the SQL affinity CASE weights).
    private(set) var affinityPoints: [UUID: [String: Double]] = [:]  // viewer -> category -> pts

    private(set) var itemsBrowsed = 0
    private(set) var fairnessItemsBrowsed = 0

    /// Mirror of FeedQueueService's per-viewer state: ranked entries + cursor.
    private struct SimQueue {
        var entries: [RankedDream] = []
        var cursor = 0
        var remaining: Int { entries.count - cursor }
    }

    private var queues: [UUID: SimQueue] = [:]
    private var rankSeed: UInt64 = 0

    init(config: RankingConfig = .default, now: Date, dreams: [SimDream], viewers: [ViewerProfile]) {
        self.config = config
        self.now = now
        self.dreams = dreams
        self.viewers = viewers
    }

    // MARK: - Time

    func advance(days: Double) {
        now = now.addingTimeInterval(days * 86_400)
    }

    // MARK: - Engagement (trigger semantics from 0022_engagement.sql)

    func recordView(viewer: UUID, dream: UUID) {
        var viewerSeen = seen[viewer] ?? [:]
        if var entry = viewerSeen[dream] {
            entry.lastSeenAt = now
            entry.seenCount += 1
            viewerSeen[dream] = entry
            // Existing row: impressions bump only, distinct viewers unchanged.
            impressions[dream, default: 0] += 1
        } else {
            viewerSeen[dream] = SeenEntry(firstSeenAt: now, lastSeenAt: now, seenCount: 1, dismissed: false)
            impressions[dream, default: 0] += 1
            distinctViewers[dream, default: []].insert(viewer)
        }
        seen[viewer] = viewerSeen
    }

    /// Skip is log-only server-side: it adjusts the skipping viewer's own
    /// affinity and touches NOTHING global — no counter, no per-dream state.
    func recordSkip(viewer: UUID, dream: UUID) {
        adjustAffinity(viewer: viewer, dream: dream, points: -0.3)
    }

    func recordComplete(viewer: UUID, dream: UUID) {
        adjustAffinity(viewer: viewer, dream: dream, points: 1.0)
    }

    func recordOffer(viewer: UUID, dream: UUID) {
        offersReceived[dream, default: 0] += 1
        adjustAffinity(viewer: viewer, dream: dream, points: 1.5)
    }

    func recordDismiss(viewer: UUID, dream: UUID) {
        var viewerSeen = seen[viewer] ?? [:]
        if var entry = viewerSeen[dream] {
            entry.dismissed = true
            entry.lastSeenAt = now
            viewerSeen[dream] = entry
        } else {
            viewerSeen[dream] = SeenEntry(firstSeenAt: now, lastSeenAt: now, seenCount: 1, dismissed: true)
        }
        seen[viewer] = viewerSeen
        adjustAffinity(viewer: viewer, dream: dream, points: -1.0)
    }

    private func adjustAffinity(viewer: UUID, dream: UUID, points: Double) {
        guard let simDream = dreams.first(where: { $0.id == dream }) else { return }
        var byCategory = affinityPoints[viewer] ?? [:]
        byCategory[simDream.category, default: 0] += points
        affinityPoints[viewer] = byCategory
    }

    // MARK: - Viewer profile with learned affinity (mirror of get_viewer_ranking_profile)

    func profileWithAffinity(_ base: ViewerProfile) -> ViewerProfile {
        var profile = base
        let points = affinityPoints[base.userId] ?? [:]
        let maxPoints = points.values.max() ?? 0
        if maxPoints > 0 {
            profile.categoryAffinity = points.mapValues { max($0, 0) / maxPoints }
        } else {
            profile.categoryAffinity = [:]
        }
        return profile
    }

    // MARK: - Candidate generation (mirror of get_feed_candidates CTEs)

    func candidates(for viewer: ViewerProfile) -> [DreamCandidate] {
        let ttl = TimeInterval(config.seenTTLDays) * 86_400
        let viewerSeen = seen[viewer.userId] ?? [:]

        let eligible = dreams
            .filter { dream in
                guard dream.ownerId != viewer.userId else { return false }
                guard let entry = viewerSeen[dream.id] else { return true }
                return !entry.dismissed && entry.lastSeenAt <= now - ttl
            }

        let byNewest = eligible.sorted {
            $0.createdAt != $1.createdAt
                ? $0.createdAt > $1.createdAt
                : $0.id.uuidString < $1.id.uuidString
        }

        let topAffinityCategories: Set<String> = {
            let points = affinityPoints[viewer.userId] ?? [:]
            let top = points.filter { $0.value > 0 }
                .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .prefix(3)
                .map(\.key)
            return Set(top).union(viewer.categoriesOfInterest)
        }()

        var sourcesById: [UUID: Set<CandidateSource>] = [:]
        func add(_ source: CandidateSource, _ list: some Sequence<SimDream>) {
            for dream in list { sourcesById[dream.id, default: []].insert(source) }
        }

        add(.helpTypeMatch, byNewest
            .filter { !$0.helpTypes.intersection(viewer.helpTypesOffered).isEmpty }
            .prefix(120))
        add(.skillOverlap, byNewest
            .filter { $0.helpTags.contains { viewer.skills.contains(Normalize.token($0)) } }
            .prefix(60))
        add(.categoryAffinity, byNewest
            .filter { topAffinityCategories.contains($0.category) }
            .prefix(60))
        if let viewerLocation = viewer.location {
            add(.geo, byNewest
                .filter { $0.location.map(Normalize.token) == viewerLocation }
                .prefix(40))
        }
        add(.followed, byNewest
            .filter { viewer.followedOwnerIds.contains($0.ownerId) }
            .prefix(30))
        add(.fresh, byNewest
            .filter { $0.createdAt > now - 48 * 3_600 }
            .prefix(30))
        add(.underexposed, eligible
            .filter { dream in
                let viewersSoFar = distinctViewers[dream.id]?.count ?? 0
                guard viewersSoFar < config.exposureViewerFloor else { return false }
                return viewer.helpTypesOffered.isEmpty
                    || dream.helpTypes.isEmpty
                    || !dream.helpTypes.intersection(viewer.helpTypesOffered).isEmpty
            }
            .sorted { lhs, rhs in
                let lv = distinctViewers[lhs.id]?.count ?? 0
                let rv = distinctViewers[rhs.id]?.count ?? 0
                if lv != rv { return lv < rv }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .prefix(40))

        return dreams.compactMap { dream -> DreamCandidate? in
            guard let sources = sourcesById[dream.id] else { return nil }
            return DreamCandidate(
                id: dream.id,
                ownerId: dream.ownerId,
                title: "",
                category: dream.category,
                stage: dream.stage,
                location: dream.location,
                helpTags: dream.helpTags,
                helpTypes: dream.helpTypes,
                createdAt: dream.createdAt,
                offersReceived: offersReceived[dream.id] ?? 0,
                supportersCount: 0,
                impressions: impressions[dream.id] ?? 0,
                distinctViewers: distinctViewers[dream.id]?.count ?? 0,
                isFollowedOwner: viewer.followedOwnerIds.contains(dream.ownerId),
                hasVideo: true,
                sources: sources
            )
        }
    }

    // MARK: - Serving (mirror of FeedQueueService.nextPage + refill)

    /// One app session for a viewer, through the shipped serving path:
    /// draw `sessionPageSize` entries from the persistent queue (with the
    /// production refill rules), then browse the first `browsing` cards.
    /// Impressions/seen-set are recorded for BROWSED cards only — queue
    /// entries the viewer never scrolled to stay unseen server-side (and may
    /// legitimately reappear in a later refill), exactly like production.
    @discardableResult
    func serveSession(toViewerAt index: Int, browsing: Int) -> [RankedDream] {
        let viewerId = viewers[index].userId
        var queue = queues[viewerId] ?? SimQueue()

        // nextPage(count: 50): blocking refill when the draw can't be covered.
        if queue.remaining < Self.sessionPageSize {
            refill(&queue, viewerIndex: index)
        }
        let end = min(queue.cursor + Self.sessionPageSize, queue.entries.count)
        let page = Array(queue.entries[queue.cursor..<end])
        queue.cursor = end

        // Background refill below the threshold.
        if queue.remaining < config.queueRefillThreshold {
            refill(&queue, viewerIndex: index)
        }
        queues[viewerId] = queue

        // DiscoverScreen: the viewer actually watches only a prefix of the
        // served feed; each browsed card logs one view.
        let browsed = Array(page.prefix(browsing))
        for item in browsed {
            recordView(viewer: viewerId, dream: item.id)
        }
        itemsBrowsed += browsed.count
        fairnessItemsBrowsed += browsed.filter(\.isFairnessSlot).count
        return browsed
    }

    /// Mirror of FeedQueueService.refill(): fetch candidates, rank with the
    /// REAL ranker, keep the unserved tail, append fresh items (deduped
    /// against what's still queued) up to queueTargetLength.
    private func refill(_ queue: inout SimQueue, viewerIndex: Int) {
        let viewer = profileWithAffinity(viewers[viewerIndex])
        let pool = candidates(for: viewer)
        rankSeed &+= 1
        let ranked = DreamRanker.rank(
            candidates: pool,
            viewer: viewer,
            config: config,
            now: now,
            seed: rankSeed
        )
        let unserved = Array(queue.entries[queue.cursor...])
        let queuedIds = Set(unserved.map(\.id))
        let fresh = ranked
            .filter { !queuedIds.contains($0.id) }
            .prefix(max(config.queueTargetLength - unserved.count, 0))
        queue.entries = unserved + fresh
        queue.cursor = 0
    }
}
