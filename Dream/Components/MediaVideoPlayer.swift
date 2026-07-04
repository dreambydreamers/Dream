import AVKit
import SwiftUI

/// A single clip belonging to a dream, used by the profile to show the main
/// dream's videos. `storagePath` points into the private `dream-videos` bucket.
struct DreamMedia: Identifiable, Hashable {
    let id: UUID
    let storagePath: String
    let posterURL: URL?
    let isPrimary: Bool
}

/// Full-screen looping player for a single `DreamMedia` clip. Signs the private
/// storage URL on appear and plays it; tap the close button to dismiss.
struct MediaVideoPlayer: View {
    let media: DreamMedia
    var onClose: () -> Void = {}

    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @StateObject private var videoActions = VideoActionsModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
            }

            VStack {
                HStack(spacing: 12) {
                    Spacer()
                    GlassCircleButton(systemName: "arrow.down.to.line", accessibilityLabel: "Save video") {
                        videoActions.save(storagePath: media.storagePath)
                    }
                    GlassCircleButton(systemName: "square.and.arrow.up", accessibilityLabel: "Share video") {
                        videoActions.share(storagePath: media.storagePath)
                    }
                    GlassCircleButton(systemName: "xmark", accessibilityLabel: "Close", action: onClose)
                }
                .padding(.horizontal, 16)
                .padding(.top, 56)
                Spacer()
            }
        }
        .task(id: media.id) { await start() }
        .onDisappear { stop() }
        .videoActions(videoActions)
    }

    private func start() async {
        guard let url = try? await VideoUploader.shared.signedVideoURL(storagePath: media.storagePath) else {
            return
        }
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer()
        let loop = AVPlayerLooper(player: queue, templateItem: item)
        stop()
        player = queue
        looper = loop
        queue.play()
    }

    private func stop() {
        player?.pause()
        player?.removeAllItems()
        player = nil
        looper = nil
    }
}
