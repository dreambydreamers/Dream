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

    @State private var player: AVPlayer?

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
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Color.black.opacity(0.45), in: Circle())
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 56)
                Spacer()
            }
        }
        .task(id: media.id) { await start() }
        .onDisappear { player?.pause() }
    }

    private func start() async {
        guard let url = try? await VideoUploader.shared.signedVideoURL(storagePath: media.storagePath) else {
            return
        }
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.actionAtItemEnd = .none
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            p.seek(to: .zero)
            p.play()
        }
        player = p
        p.play()
    }
}
