import AVFoundation
import SwiftUI
import UIKit

/// Shared building blocks for the "compose a clip" flows (new dream + dream
/// update), so both screens render the same source cards, preview and pickers
/// without duplicating their layout - for CreateDreamScreen and PostUpdateScreen

/// Generates a poster frame ~0.5s into a video, for use as a compose preview.
func loadVideoThumbnail(from url: URL) async -> UIImage? {
    let asset = AVURLAsset(url: url)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 1080, height: 1080)
    let time = CMTime(seconds: 0.5, preferredTimescale: 600)
    guard let cgImage = try? await generator.image(at: time).image else { return nil }
    return UIImage(cgImage: cgImage)
}

/// A tappable "Record video" / "Choose from library" source card.
struct VideoSourceCard: View {
    let icon: String
    let title: String
    let sub: String
    var tinted: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(tinted ? Color.white : DreamTheme.bg)
                        .shadow(color: tinted ? DreamTheme.blue.opacity(0.15) : .clear, radius: 12, y: 4)
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(DreamTheme.blue)
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(DreamTheme.Font.text(17, weight: .semibold))
                        .foregroundStyle(DreamTheme.ink)
                    Text(sub)
                        .font(DreamTheme.Font.text(13))
                        .foregroundStyle(DreamTheme.ink2)
                }
                Spacer()
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(tinted
                          ? LinearGradient(colors: [DreamTheme.blueSoft, .white], startPoint: .topLeading, endPoint: .bottomTrailing)
                          : LinearGradient(colors: [.white, .white], startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(tinted ? DreamTheme.blue : DreamTheme.line, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Preview of a picked clip — a 16:9 card with a play glyph and a "re-pick"
/// affordance. Falls back to the category gradient until the thumbnail is ready.
struct VideoPreviewCard: View {
    let thumbnail: UIImage?
    let category: DreamCategory
    var rePickLabel: String = "Re-record"
    let onRePick: () -> Void
    /// Optional "Save to Photos" affordance for the picked clip. When nil, the
    /// save pill is hidden (e.g. previews where saving doesn't apply).
    var onSave: (() -> Void)? = nil

    var body: some View {
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    ZStack {
                        if let thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .clipped()
                        } else {
                            ScenePoster(category: category)
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .clipped()
                        }

                        Circle()
                            .fill(Color.black.opacity(0.4))
                            .background(.ultraThinMaterial, in: Circle())
                            .frame(width: 52, height: 52)
                            .overlay(
                                Image(systemName: "play.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .offset(x: 2)
                            )

                        VStack {
                            HStack(spacing: 8) {
                                Spacer()
                                if let onSave {
                                    Button(action: onSave) {
                                        HStack(spacing: 5) {
                                            Image(systemName: "arrow.down.to.line")
                                            Text("Save")
                                        }
                                        .font(DreamTheme.Font.text(12, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.black.opacity(0.5), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                                Button(rePickLabel, action: onRePick)
                                    .font(DreamTheme.Font.text(12, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.black.opacity(0.5), in: Capsule())
                            }
                            Spacer()
                        }
                        .padding(10)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
    }
}

/// Preview of a picked photo update. The image is bounded so portrait photos
/// cannot push the details form off-screen.
struct PhotoPreviewCard: View {
    let image: UIImage?
    let category: DreamCategory
    var rePickLabel: String = "Re-pick"
    let onRePick: () -> Void

    var body: some View {
        Color.clear
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    ZStack(alignment: .topTrailing) {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(DreamTheme.bg)

                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: proxy.size.width, height: proxy.size.height)
                        } else {
                            ScenePoster(category: category)
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .clipped()
                        }

                        Button(rePickLabel, action: onRePick)
                            .font(DreamTheme.Font.text(12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.5), in: Capsule())
                            .buttonStyle(.plain)
                            .padding(10)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(DreamTheme.line, lineWidth: 1)
                    )
                }
            }
    }
}

extension View {
    /// Attaches the camera recorder (full-screen) and library picker (sheet),
    /// handing the picked file URL back through `onPick`.
    func videoSourcePicker(
        showCamera: Binding<Bool>,
        showLibrary: Binding<Bool>,
        onPick: @escaping (URL) -> Void
    ) -> some View {
        self
            .fullScreenCover(isPresented: showCamera) {
                VideoRecorder { onPick($0) }.ignoresSafeArea()
            }
            .sheet(isPresented: showLibrary) {
                VideoLibraryPicker { onPick($0) }.ignoresSafeArea()
            }
    }
}
