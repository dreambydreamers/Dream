import AVFoundation
import Foundation

/// Prepares feed videos ahead of time so playback starts as fast as possible —
/// both when scrolling between dreams and on the very first video.
///
/// Layers:
///   1. Signed URLs (valid ~1h) are cached so re-visiting a dream never
///      re-hits the network.
///   2. A small LRU pool of fully-built, pre-buffered `AVQueuePlayer`s is kept
///      warm for the current dream and its neighbours.
///   3. Each player lowers its buffer threshold and `preroll`s (priming the
///      decode pipeline) the moment it reports `.readyToPlay`, so the first
///      frame appears with minimal delay.
///   4. Builds are coalesced per-dream, so an early prefetch and the view's own
///      load share one player instead of racing to create two.
@MainActor
final class FeedVideoPreloader {
    static let shared = FeedVideoPreloader()

    private struct Prepared {
        let player: AVQueuePlayer
        let looper: AVPlayerLooper
    }

    private var players: [UUID: Prepared] = [:]
    private var lru: [UUID] = []                       // most-recent last
    private var signedURLs: [UUID: (url: URL, expires: Date)] = [:]
    private var building: [UUID: Task<Prepared?, Never>] = [:]
    private var statusObservers: [UUID: NSKeyValueObservation] = [:]
    private let maxPlayers = 4
    private var audioConfigured = false

    /// The discover feed's currently-visible card. Set by `DiscoverScreen` while
    /// the feed is on screen, cleared when it leaves. A `fullScreenCover` (dream
    /// detail / profile) freezes the presenter, so the feed view can't pause
    /// itself — the covering screen drives `pauseFeedPlayer()`/`resumeFeedPlayer()`
    /// against this id instead.
    var feedActiveID: UUID?
    /// The feed's desired mute state, restored when the feed resumes (a covering
    /// detail page may have toggled mute on a player it shares with the feed).
    var feedMuted: Bool = false

    /// How many full-screen covers (detail / profile, possibly nested) are over
    /// the feed. The feed only resumes once the last one closes.
    private var feedCoverDepth = 0

    private init() {}

    /// Pause the feed's current player while a full-screen cover is shown over it.
    func pauseFeedPlayer() {
        feedCoverDepth += 1
        guard let id = feedActiveID, let prepared = players[id] else { return }
        prepared.player.pause()
    }

    /// Balance a `pauseFeedPlayer()`. Resumes the feed only when the outermost
    /// cover closes. Deferred a runloop tick so it lands *after* the covering
    /// view's own `onDisappear` (which may pause a player shared with the feed),
    /// regardless of teardown order.
    func resumeFeedPlayer() {
        feedCoverDepth = max(0, feedCoverDepth - 1)
        guard feedCoverDepth == 0, let id = feedActiveID else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.feedCoverDepth == 0, let prepared = self.players[id] else { return }
            prepared.player.isMuted = self.feedMuted
            prepared.player.play()
        }
    }

    // MARK: - Public

    /// Returns a warm, looping player for the dream, building + pre-buffering
    /// one on the spot if it wasn't already prefetched. The player is returned
    /// paused at the start; the caller decides when to `play()`.
    func player(for dream: Dream, isMuted: Bool) async -> AVQueuePlayer? {
        guard let prepared = await build(for: dream, isMuted: isMuted) else { return nil }
        prepared.player.isMuted = isMuted
        return prepared.player
    }

    /// Warm up a dream's player in the background without playing it, so it's
    /// buffered by the time the user scrolls to it.
    func prefetch(_ dream: Dream) {
        guard dream.videoStoragePath != nil, players[dream.feedID] == nil else { return }
        Task { [weak self] in _ = await self?.build(for: dream, isMuted: true) }
    }

    /// Prefetch the current dream plus its nearest neighbours.
    func prefetchNeighbors(of dreams: [Dream], around index: Int) {
        guard !dreams.isEmpty else { return }
        let count = dreams.count
        // Current + immediate neighbours only. Each prefetch eagerly buffers
        // ~1s of video, so a tighter window means less wasted egress on cards
        // the user may never reach.
        for offset in [0, 1, -1] {
            let i = ((index + offset) % count + count) % count
            prefetch(dreams[i])
        }
    }

    // MARK: - Building (coalesced per dream)

    private func build(for dream: Dream, isMuted: Bool) async -> Prepared? {
        let key = dream.feedID
        if let prepared = players[key] {
            touch(key)
            return prepared
        }
        if let inFlight = building[key] {
            return await inFlight.value
        }
        let task = Task { [weak self] () -> Prepared? in
            await self?.makePrepared(for: dream, isMuted: isMuted)
        }
        building[key] = task
        let result = await task.value
        building[key] = nil
        return result
    }

    private func makePrepared(for dream: Dream, isMuted: Bool) async -> Prepared? {
        guard let url = await signedURL(for: dream) else { return nil }

        configureAudioSessionIfNeeded()

        let item = AVPlayerItem(url: url)
        // Reach `.readyToPlay` after buffering ~1s rather than the larger
        // automatic default — gets the first frame on screen sooner.
        item.preferredForwardBufferDuration = 1

        let queue = AVQueuePlayer(playerItem: item)
        queue.isMuted = isMuted
        // Start as soon as enough is buffered instead of waiting to minimise
        // stalls — feels snappier in a vertical feed.
        queue.automaticallyWaitsToMinimizeStalling = false
        let looper = AVPlayerLooper(player: queue, templateItem: item)

        // Prime the decode pipeline once the player is ready. `preroll` throws
        // if called before `.readyToPlay`, so gate it on the status observer.
        primePrerollWhenReady(dream.feedID, queue)

        let prepared = Prepared(player: queue, looper: looper)
        store(dream.feedID, prepared)
        return prepared
    }

    /// Observe the player's status and `preroll` exactly once it's ready, which
    /// decodes initial frames so the eventual `play()` shows video immediately.
    private func primePrerollWhenReady(_ id: UUID, _ queue: AVQueuePlayer) {
        statusObservers[id]?.invalidate()
        statusObservers[id] = queue.observe(\.status, options: [.initial, .new]) { player, _ in
            guard player.status == .readyToPlay else { return }
            player.preroll(atRate: 1) { _ in }
        }
    }

    private func signedURL(for dream: Dream) async -> URL? {
        guard let path = dream.videoStoragePath else { return nil }
        if let cached = signedURLs[dream.feedID], cached.expires > Date().addingTimeInterval(120) {
            return cached.url
        }
        guard let url = try? await VideoUploader.shared.signedVideoURL(storagePath: path) else { return nil }
        signedURLs[dream.feedID] = (url, Date().addingTimeInterval(3600))
        return url
    }

    // MARK: - LRU bookkeeping

    private func store(_ id: UUID, _ prepared: Prepared) {
        players[id] = prepared
        touch(id)
        while lru.count > maxPlayers, let oldest = lru.first {
            lru.removeFirst()
            statusObservers[oldest]?.invalidate()
            statusObservers[oldest] = nil
            if let evicted = players.removeValue(forKey: oldest) {
                evicted.player.pause()
                evicted.player.removeAllItems()
            }
        }
    }

    private func touch(_ id: UUID) {
        lru.removeAll { $0 == id }
        lru.append(id)
    }

    private func configureAudioSessionIfNeeded() {
        guard !audioConfigured else { return }
        audioConfigured = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
    }
}

import SwiftUI

extension View {
    /// Pauses the discover feed's video while this presented screen (a sheet or
    /// cover shown over the feed) is on screen, and resumes it — once the last
    /// cover closes — when the screen is dismissed. Balanced via the preloader's
    /// cover-depth counter, so it nests safely with other paused covers.
    func pausesDiscoverFeed() -> some View {
        self
            .onAppear { FeedVideoPreloader.shared.pauseFeedPlayer() }
            .onDisappear { FeedVideoPreloader.shared.resumeFeedPlayer() }
    }
}
