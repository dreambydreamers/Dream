import AVFoundation
import SwiftUI
import UIKit

/// Full-bleed feed background for a dream (TikTok-style).
///
/// Shows the poster image immediately, then plays the dream's video — looping,
/// with sound on by default — once a signed URL is fetched from the private
/// `dream-videos` bucket. Tap anywhere to pause/resume. Falls back to the
/// procedural `ScenePoster` gradient when the dream has no uploaded media.
struct DreamVideoBackground: View {
    let dream: Dream
    var isMuted: Bool = false

    @State private var player: AVQueuePlayer?
    @State private var isPlaying = true

    var body: some View {
        // A single GeometryReader pins every layer to the container's bounds.
        // `scaledToFill` and the AVPlayerLayer otherwise report the media's
        // natural dimensions for *layout* (clipped() only clips drawing), which
        // would inflate this view and shift the feed's overlay content.
        GeometryReader { geo in
            ZStack {
                // Base layer: poster image if we have one, else the gradient.
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
                if let player {
                    VideoLayerView(player: player)
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
        .task(id: dream.id) { await loadVideo() }
        .onChange(of: isMuted) { _, muted in player?.isMuted = muted }
        .onDisappear {
            // Just pause — the preloader owns the player's lifecycle so it
            // stays warm in the cache for an instant restart.
            player?.pause()
            player = nil
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
        isPlaying = true
        guard let queue = await FeedVideoPreloader.shared.player(for: dream, isMuted: isMuted) else {
            player = nil
            return
        }
        queue.isMuted = isMuted
        await queue.seek(to: .zero)
        queue.play()
        player = queue
    }
}

/// Hosts an `AVPlayerLayer` so the video fills the frame (aspect-fill),
/// matching the poster image behind it.
private struct VideoLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
