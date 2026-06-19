import Foundation
import Supabase
import UIKit

/// Uploads a profile picture to the public `avatars` bucket and returns its
/// public URL (with a cache-busting query). Mirrors `VideoUploader`'s storage
/// conventions — most importantly the lowercased user-id path folder, which the
/// storage RLS policy requires (see CLAUDE.md "Storage RLS path gotcha").
@MainActor
final class AvatarUploader {
    static let shared = AvatarUploader()
    private let client = SupabaseService.shared.client
    private init() {}

    /// Max edge of the stored image. Avatars only ever render small, so 512px
    /// keeps the file well under the bucket's 2 MB limit.
    private let maxEdge: CGFloat = 512

    /// Resizes/crops the image to a square, uploads it (overwriting any previous
    /// avatar at the same path), and returns the public URL to store in
    /// `profiles.avatar_url`.
    func upload(_ image: UIImage) async throws -> String {
        guard let userId = try? await client.auth.session.user.id else {
            throw NSError(domain: "AvatarUploader", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }
        guard let data = squareJPEG(image) else {
            throw NSError(domain: "AvatarUploader", code: 422,
                          userInfo: [NSLocalizedDescriptionKey: "Couldn't process the image"])
        }

        // Lowercase the user-id folder to satisfy storage RLS (auth.uid() is
        // rendered lowercase; UUID.uuidString is uppercase).
        let path = "\(userId.uuidString.lowercased())/avatar.jpg"
        _ = try await client.storage
            .from("avatars")
            .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))

        // Public bucket: a stable URL per path. Bust the AsyncImage cache after an
        // overwrite by appending a version query.
        let publicURL = try client.storage.from("avatars").getPublicURL(path: path)
        let busted = publicURL.absoluteString + "?v=\(Int(Date().timeIntervalSince1970))"
        return busted
    }

    /// Deletes the stored avatar object (best effort). The caller also clears
    /// `profiles.avatar_url`.
    func remove() async throws {
        guard let userId = try? await client.auth.session.user.id else { return }
        let path = "\(userId.uuidString.lowercased())/avatar.jpg"
        _ = try? await client.storage.from("avatars").remove(paths: [path])
    }

    // MARK: - Helpers

    /// Center-crops to a square and downscales to `maxEdge`, returning JPEG data
    /// (drops quality if needed to stay comfortably under the 2 MB limit).
    private func squareJPEG(_ image: UIImage) -> Data? {
        let normalized = image.fixedOrientation()
        let shortEdge = min(normalized.size.width, normalized.size.height)
        let cropRect = CGRect(
            x: (normalized.size.width - shortEdge) / 2,
            y: (normalized.size.height - shortEdge) / 2,
            width: shortEdge, height: shortEdge
        )
        let cropped: UIImage
        if let cg = normalized.cgImage?.cropping(to: CGRect(
            x: cropRect.origin.x * normalized.scale,
            y: cropRect.origin.y * normalized.scale,
            width: cropRect.width * normalized.scale,
            height: cropRect.height * normalized.scale
        )) {
            cropped = UIImage(cgImage: cg)
        } else {
            cropped = normalized
        }

        let side = min(maxEdge, cropped.size.width)
        let target = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            cropped.draw(in: CGRect(origin: .zero, size: target))
        }

        for quality in [0.8, 0.6, 0.4] as [CGFloat] {
            if let data = resized.jpegData(compressionQuality: quality), data.count < 2_000_000 {
                return data
            }
        }
        return resized.jpegData(compressionQuality: 0.3)
    }
}

private extension UIImage {
    /// Redraws the image upright so the stored JPEG isn't rotated.
    func fixedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
