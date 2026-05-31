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
    @State private var looper: AVPlayerLooper?
    @State private var isPlaying = true

    var body: some View {
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
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { togglePlayback() }
        .task(id: dream.id) { await loadVideo() }
        .onChange(of: isMuted) { _, muted in player?.isMuted = muted }
        .onDisappear {
            player?.pause()
            player = nil
            looper = nil
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
        guard let path = dream.videoStoragePath,
              let url = try? await VideoUploader.shared.signedVideoURL(storagePath: path)
        else { return }

        configureAudioSession()

        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer(playerItem: item)
        queue.isMuted = isMuted
        looper = AVPlayerLooper(player: queue, templateItem: item)
        player = queue
        queue.play()
    }

    /// Route to .playback so video sound is audible even when the hardware
    /// ring/silent switch is set to silent.
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
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
