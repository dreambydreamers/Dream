import Foundation
import Supabase
import UIKit

/// Uploads photo updates for a dream. Images are public thumbnails/detail media,
/// while the metadata row stays protected by normal dream ownership RLS.
@MainActor
final class DreamImageUploader {
    static let shared = DreamImageUploader()
    private let client = SupabaseService.shared.client
    private init() {}

    struct UploadResult {
        let id: UUID
        let imagePath: String
        let imageURL: URL?
    }

    private let maxLongEdge: CGFloat = 1800
    private let maxBytes = 4_800_000

    func upload(
        image: UIImage,
        dreamId: UUID,
        title: String,
        caption: String?
    ) async throws -> UploadResult {
        guard let userId = try? await client.auth.session.user.id else {
            throw NSError(domain: "DreamImageUploader", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }
        guard let prepared = preparedJPEG(from: image) else {
            throw NSError(domain: "DreamImageUploader", code: 422,
                          userInfo: [NSLocalizedDescriptionKey: "Couldn't process the image"])
        }

        let imageId = UUID()
        let path = "\(userId.uuidString.lowercased())/\(dreamId.uuidString.lowercased())/\(imageId.uuidString.lowercased()).jpg"
        _ = try await client.storage
            .from("dream-images")
            .upload(path, data: prepared.data, options: FileOptions(contentType: "image/jpeg", upsert: false))

        let payload = NewPhotoUpdatePayload(
            dream_id: dreamId,
            image_path: path,
            title: title,
            caption: caption,
            width: Int(prepared.size.width),
            height: Int(prepared.size.height)
        )

        let inserted: DreamPhotoUpdateDTO = try await client
            .from("dream_photo_updates")
            .insert(payload, returning: .representation)
            .select()
            .single()
            .execute()
            .value

        let publicURL = try? client.storage.from("dream-images").getPublicURL(path: path)
        return UploadResult(id: inserted.id, imagePath: path, imageURL: publicURL)
    }

    private func preparedJPEG(from image: UIImage) -> (data: Data, size: CGSize)? {
        let normalized = image.dreamImageFixedOrientation()
        let sourceSize = normalized.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }

        let longEdge = max(sourceSize.width, sourceSize.height)
        let scale = min(1, maxLongEdge / longEdge)
        let target = CGSize(
            width: max(1, floor(sourceSize.width * scale)),
            height: max(1, floor(sourceSize.height * scale))
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            normalized.draw(in: CGRect(origin: .zero, size: target))
        }

        for quality in [0.82, 0.7, 0.55, 0.4] as [CGFloat] {
            if let data = resized.jpegData(compressionQuality: quality), data.count <= maxBytes {
                return (data, target)
            }
        }
        guard let data = resized.jpegData(compressionQuality: 0.3) else { return nil }
        return (data, target)
    }
}

private extension UIImage {
    func dreamImageFixedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
