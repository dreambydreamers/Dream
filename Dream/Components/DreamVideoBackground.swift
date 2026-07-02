import AVFoundation
import SwiftUI
import UIKit

/// Full-bleed feed background for a dream (TikTok-style).
///
/// Shows the poster image immediately, then plays the dream's video — looping,
/// with sound on by default — once a signed URL is fetched from the private
/// `dream-videos` bucket. Tap anywhere to pause/resume. Falls back to the
/// procedural `ScenePoster` gradient when the dream has no uploaded media.
///
/// Two guarantees prevent the black-screen flash seen when a plain UIViewRepresentable
/// connects to an AVPlayer:
///   1. **Synchronous fast path** — if the preloader already has the player cached,
///      `loadVideo()` sets it before any `await`, so there is zero frames with
///      `player == nil` (no poster→black→video jitter).
///   2. **isReadyForDisplay gating** — `VideoLayerView` renders at opacity 0 until
///      the AVPlayerLayer reports its first decoded frame, then instantly switches to
///      opacity 1. The poster is always visible behind it, so the user sees
///      poster → video (never poster → black → video).
struct DreamVideoBackground: View {
    let dream: Dream
    var isMuted: Bool = false

    @State private var player: AVQueuePlayer?
    @State private var isPlaying = true
    /// Tracks AVPlayerLayer.isReadyForDisplay; drives the opacity gate below.
    @State private var videoVisible = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Base layer: poster image if we have one, else the gradient.
                // Always visible — never replaced by a black frame.
                if let posterURL = dream.posterURL {
                    AsyncImage(url: posterURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            ScenePoster(category: dream.category)
                        }
                    }
                } else {
                    ScenePoster(category: dream.category)
                }

                // Video plays on top once its signed URL is ready.
                // opacity(0) while the layer hasn't rendered its first frame so the
                // poster shows through; flips to 1 the moment isReadyForDisplay fires.
                if let player {
                    VideoLayerView(player: player, onReadyChange: { ready in
                        videoVisible = ready
                    })
                    .opacity(videoVisible ? 1 : 0)
                }

                // Centered play glyph while paused.
                if player != nil && !isPlaying {
                    Image(systemName: "play.fill")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.4), radius: 10)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { togglePlayback() }
        }
        .task(id: dream.feedID) { await loadVideo() }
        .onChange(of: isMuted) { _, muted in player?.isMuted = muted }
        .onDisappear {
            // Just pause — the preloader owns the player's lifecycle so it
            // stays warm in the cache for an instant restart.
            let disappearingPlayer = player
            let id = dream.feedID
            player = nil
            DispatchQueue.main.async {
                if FeedVideoPreloader.shared.feedActiveID != id {
                    disappearingPlayer?.pause()
                }
            }
        }
    }

    private func togglePlayback() {
        guard let player else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            if isPlaying { player.pause() } else { player.play() }
            isPlaying.toggle()
        }
    }

    private func loadVideo() async {
        // Reset visibility gate for the incoming dream; poster shows until the
        // new player's first frame is rendered.
        videoVisible = false
        isPlaying = true
        if let existing = player { existing.pause() }

        // Synchronous fast path: the preloader already has this player built and
        // prerolled — grab it without any `await` so there are zero frames where
        // `player == nil`. The VideoLayerView connects immediately and
        // isReadyForDisplay fires on the very next run-loop tick.
        if let cached = FeedVideoPreloader.shared.cachedPlayer(for: dream) {
            cached.isMuted = isMuted
            player = cached
            cached.seek(to: .zero) { _ in }
            cached.play()
            return
        }

        // Slow path: build the player (signed URL fetch + AVPlayerItem creation +
        // preroll). Shows the poster/gradient until player is ready.
        guard let queue = await FeedVideoPreloader.shared.player(for: dream, isMuted: isMuted) else {
            player = nil
            return
        }
        queue.isMuted = isMuted
        // Set player before play() so VideoLayerView connects and isReadyForDisplay
        // can fire while the player is warming up — no black gap.
        player = queue
        queue.seek(to: .zero) { _ in }
        queue.play()
    }
}

/// Hosts an `AVPlayerLayer` so the video fills the frame (aspect-fill),
/// matching the poster image behind it.
private struct VideoLayerView: UIViewRepresentable {
    let player: AVPlayer
    /// Called on the main thread whenever AVPlayerLayer.isReadyForDisplay changes.
    var onReadyChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        context.coordinator.observe(view.playerLayer, onReadyChange: onReadyChange)
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        // Only re-attach and re-observe when the underlying player object changes
        // (e.g. a new dream loaded into this slot) to avoid redundant KVO churn.
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
            context.coordinator.observe(uiView.playerLayer, onReadyChange: onReadyChange)
        }
    }

    final class Coordinator: NSObject {
        private var obs: NSKeyValueObservation?

        func observe(_ layer: AVPlayerLayer, onReadyChange: @escaping (Bool) -> Void) {
            obs?.invalidate()
            obs = layer.observe(\.isReadyForDisplay, options: [.initial, .new]) { l, _ in
                let ready = l.isReadyForDisplay
                DispatchQueue.main.async { onReadyChange(ready) }
            }
        }
    }
}

private final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
