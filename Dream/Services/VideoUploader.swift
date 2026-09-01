import AVFoundation
import Foundation
import Supabase
import UIKit

/// Uploads a video to the private `dream-videos` bucket, generates a poster frame,
/// uploads the poster to the public `dream-posters` bucket, and inserts a
/// `dream_videos` row pointing at both.
@MainActor
final class VideoUploader {
    static let shared = VideoUploader()
    private let client = SupabaseService.shared.client
    private init() {}

    /// Refuse anything past this rather than let the upload fail obscurely at
    /// the bucket's 500 MB ceiling. A transcoded ~6 Mbps clip hits this at
    /// roughly four minutes, well beyond anything the composer produces.
    private static let maxUploadBytes = 200_000_000

    struct UploadResult {
        let videoId: UUID
        let storagePath: String
        let posterPath: String?
    }

    /// - Parameters:
    ///   - localVideoURL: a file URL to the video on disk (e.g. from PHPickerViewController)
    ///   - dreamId: the dream this video belongs to
    ///   - markPrimary: whether to mark this as the primary/cover video
    ///   - title: optional per-video heading (used by "update" clips); the cover
    ///     video leaves this nil and inherits the dream's title in the feed.
    ///   - caption: optional per-video caption used by Explore update details.
    func upload(
        localVideoURL: URL,
        dreamId: UUID,
        markPrimary: Bool = true,
        title: String? = nil,
        caption: String? = nil
    ) async throws -> UploadResult {
        guard let userId = try? await client.auth.session.user.id else {
            throw NSError(domain: "VideoUploader", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }

        let videoId = UUID()
        // Storage RLS compares the first path folder to auth.uid()::text, which
        // Postgres renders lowercase. Swift's UUID.uuidString is uppercase, so
        // lowercase the whole path to match (otherwise: 403 RLS violation).
        let userFolder = userId.uuidString.lowercased()
        let videoPath = "\(userFolder)/\(dreamId.uuidString.lowercased())/\(videoId.uuidString.lowercased()).mp4"

        // 0) Transcode to a sane mobile bitrate (~6 Mbps) before upload. Camera
        // captures are ~15 Mbps full-HD — far more than the feed shows — so this
        // cuts stored size and every byte of playback egress by ~60%. Falls back
        // to the original on failure; a temp file is cleaned up after upload.
        let encoded = (try? await VideoTranscoder.transcode(localVideoURL)) ?? localVideoURL
        defer {
            if encoded != localVideoURL { try? FileManager.default.removeItem(at: encoded) }
        }

        // 1) Upload the video.
        // Streamed from disk rather than `Data(contentsOf:)` — the bucket takes
        // objects up to 500 MB, and reading one of those into memory on a phone
        // gets the app jetsammed mid-publish. The cap below rejects the
        // pathological case with a message instead of a crash.
        let sizeBytes = (try? FileManager.default
            .attributesOfItem(atPath: encoded.path))?[.size] as? Int
        if let sizeBytes, sizeBytes > Self.maxUploadBytes {
            throw NSError(domain: "VideoUploader", code: 413, userInfo: [
                NSLocalizedDescriptionKey:
                    "That video is too large to upload. Try a shorter clip."
            ])
        }
        _ = try await client.storage
            .from("dream-videos")
            .upload(
                videoPath,
                fileURL: encoded,
                options: FileOptions(contentType: "video/mp4", upsert: false)
            )

        // 2) Probe metadata + extract poster (from the encoded file, so the
        //    stored width/height/duration match what was uploaded)
        let asset = AVURLAsset(url: encoded)
        let duration = (try? await asset.load(.duration)) ?? .zero
        let durationMs = Int(CMTimeGetSeconds(duration) * 1000)
        let track = try? await asset.loadTracks(withMediaType: .video).first
        let size = (try? await track?.load(.naturalSize)) ?? .zero

        // A poster is optional, so a failure here must not fail the publish —
        // but only record the path if the object actually landed. Assigning it
        // unconditionally (as this did) writes a poster_path that 404s forever,
        // and the feed then shows a permanently broken thumbnail.
        var posterPath: String? = nil
        if let posterData = await generatePoster(from: asset) {
            let path = "\(userFolder)/\(dreamId.uuidString.lowercased())/\(videoId.uuidString.lowercased()).jpg"
            do {
                _ = try await client.storage
                    .from("dream-posters")
                    .upload(
                        path,
                        data: posterData,
                        options: FileOptions(contentType: "image/jpeg", upsert: false)
                    )
                posterPath = path
            } catch {
                print("[VideoUploader] poster upload failed, continuing without one: \(error)")
            }
        }

        // 3) Insert the dream_videos row
        let payload = NewVideoPayload(
            dream_id: dreamId,
            storage_path: videoPath,
            poster_path: posterPath,
            duration_ms: durationMs > 0 ? durationMs : nil,
            width: Int(size.width) > 0 ? Int(size.width) : nil,
            height: Int(size.height) > 0 ? Int(size.height) : nil,
            is_primary: markPrimary,
            title: title,
            caption: caption
        )
        _ = try await client.from("dream_videos").insert(payload).execute()

        return UploadResult(videoId: videoId, storagePath: videoPath, posterPath: posterPath)
    }

    /// Returns a 60-minute signed URL for a private video object.
    func signedVideoURL(storagePath: String, expiresIn seconds: Int = 3600) async throws -> URL {
        return try await client.storage
            .from("dream-videos")
            .createSignedURL(path: storagePath, expiresIn: seconds)
    }

    // MARK: - Helpers

    private func generatePoster(from asset: AVAsset) async -> Data? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1080, height: 1920)
        let time = CMTimeMake(value: 1, timescale: 2) // 0.5s in
        guard let cgImage = try? await generator.image(at: time).image else {
            return nil
        }
        let image = UIImage(cgImage: cgImage)
        return image.jpegData(compressionQuality: 0.7)
    }
}
