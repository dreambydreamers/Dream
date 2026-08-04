import Foundation
import Combine
import SwiftUI
import UIKit

/// Cached poster image used by feed/profile/chat video thumbnails.
struct PosterImage: View {
    let url: URL?
    let category: DreamCategory

    @StateObject private var loader = PosterImageLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ScenePoster(category: category)
            }
        }
        .task(id: url) {
            await loader.load(url)
        }
    }
}

@MainActor
private final class PosterImageLoader: ObservableObject {
    @Published var image: UIImage?

    /// Bounded on purpose: the Explore grid can decode hundreds of posters in
    /// one session, and an unlimited NSCache holds every one of them until the
    /// system issues a memory warning.
    private static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 120
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()
    private var loadedURL: URL?

    func load(_ url: URL?) async {
        guard loadedURL != url else { return }
        loadedURL = url

        guard let url else {
            image = nil
            return
        }

        let key = url as NSURL
        if let cached = Self.cache.object(forKey: key) {
            image = cached
            return
        }

        image = nil
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let decoded = UIImage(data: data) else { return }
            // Cost is the decoded footprint, not the JPEG's — that is what
            // `totalCostLimit` needs to bound.
            let cost = Int(decoded.size.width * decoded.size.height * decoded.scale * decoded.scale) * 4
            Self.cache.setObject(decoded, forKey: key, cost: cost)
            if loadedURL == url {
                image = decoded
            }
        } catch {
            if loadedURL == url {
                image = nil
            }
        }
    }
}
