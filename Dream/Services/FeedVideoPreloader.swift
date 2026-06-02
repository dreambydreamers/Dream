import AVFoundation
import Foundation

/// Prepares feed videos ahead of time so scrolling between dreams starts
/// playback instantly instead of waiting on a signed-URL fetch + cold buffer.
///
/// Two layers of caching:
///   1. Signed URLs (valid ~1h) are cached so re-visiting a dream never
///      re-hits the network.
///   2. A small LRU pool of fully-built, pre-buffered `AVQueuePlayer`s is kept
///      warm for the current dream and its neighbours. When the user scrolls,
///      `DreamVideoBackground` grabs the already-prepared player and just calls
///      `play()`.
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
    private var inFlight: Set<UUID> = []
    private let maxPlayers = 4
    private var audioConfigured = false

    private init() {}

    // MARK: - Public

    /// Returns a warm, looping player for the dream, building + pre-buffering
    /// one on the spot if it wasn't already prefetched. The player is returned
    /// paused at the start; the caller decides when to `play()`.
    func player(for dream: Dream, isMuted: Bool) async -> AVQueuePlayer? {
        if let prepared = players[dream.id] {
            touch(dream.id)
            prepared.player.isMuted = isMuted
            return prepared.player
        }
        guard let prepared = await build(for: dream, isMuted: isMuted) else { return nil }
        return prepared.player
    }

    /// Warm up a dream's player in the background without playing it, so it's
    /// buffered by the time the user scrolls to it.
    func prefetch(_ dream: Dream) {
        guard dream.videoStoragePath != nil,
              players[dream.id] == nil,
              !inFlight.contains(dream.id) else { return }
        inFlight.insert(dream.id)
        Task { [weak self] in
            _ = await self?.build(for: dream, isMuted: true)
            self?.inFlight.remove(dream.id)
        }
    }

    /// Convenience: prefetch the dreams immediately before/after `index`.
    func prefetchNeighbors(of dreams: [Dream], around index: Int) {
        guard !dreams.isEmpty else { return }
        let count = dreams.count
        for offset in [1, -1, 2] {
            let i = ((index + offset) % count + count) % count
            prefetch(dreams[i])
        }
    }

    // MARK: - Building

    private func build(for dream: Dream, isMuted: Bool) async -> Prepared? {
        if let prepared = players[dream.id] {
            touch(dream.id)
            return prepared
        }
        guard let url = await signedURL(for: dream) else { return nil }

        configureAudioSessionIfNeeded()

        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer(playerItem: item)
        queue.isMuted = isMuted
        // Start playback as soon as enough is buffered rather than waiting to
        // minimise stalls — feels snappier in a vertical feed.
        queue.automaticallyWaitsToMinimizeStalling = false
        let looper = AVPlayerLooper(player: queue, templateItem: item)

        // Building the player + item already begins loading the asset and
        // buffering ahead of the user reaching this dream. (Don't call
        // `preroll` here — it throws unless the player is already
        // `.readyToPlay`, which it isn't yet right after creation.)

        let prepared = Prepared(player: queue, looper: looper)
        store(dream.id, prepared)
        return prepared
    }

    private func signedURL(for dream: Dream) async -> URL? {
        guard let path = dream.videoStoragePath else { return nil }
        if let cached = signedURLs[dream.id], cached.expires > Date().addingTimeInterval(120) {
            return cached.url
        }
        guard let url = try? await VideoUploader.shared.signedVideoURL(storagePath: path) else { return nil }
        signedURLs[dream.id] = (url, Date().addingTimeInterval(3600))
        return url
    }

    // MARK: - LRU bookkeeping

    private func store(_ id: UUID, _ prepared: Prepared) {
        players[id] = prepared
        touch(id)
        while lru.count > maxPlayers, let oldest = lru.first {
            lru.removeFirst()
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
